#!/usr/bin/env bash
set -euo pipefail

# HOW TO USE
#
# Purpose:
#   Run Fireblocks install.sh non-interactively by reading install parameters
#   from local files, avoiding manual paste of the callback public key.
#
# Default usage:
#   cd /home/ec2-user
#   ./run_install_from_files.sh
#
# Optional explicit paths:
#   ./run_install_from_files.sh <input_file> <callback_public_key_pem> <install_sh>
#
# Defaults:
#   input_file              ./e2e-t2.txt
#   callback_public_key_pem ./callback_public.pem
#   install_sh              ./install.sh
#
# input_file format:
#   The first 4 non-empty lines are read in this exact order:
#
#     line 1: KMS CMK ARN
#     line 2: S3 bucket name only
#     line 3: callback URL
#     line 4: Fireblocks pairing token
#
#   Example:
#
#     arn:aws:kms:ap-northeast-1:123456789012:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#     my-cosigner-bucket-123456789012
#     https://example.execute-api.ap-northeast-1.amazonaws.com/dev/callback
#     eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...
#
# input_file constraints:
#   - Blank lines are ignored.
#   - Do not include "s3://" or "arn:aws:s3:::" in line 2; use the plain bucket name.
#   - The pairing token must be a single-line JWT and must not be expired.
#   - Extra non-empty lines after line 4 are ignored.
#
# callback_public_key_pem constraints:
#   - Must be a PEM public key accepted by:
#       openssl rsa -pubin -in <file> -noout
#   - Keep the standard markers:
#       -----BEGIN PUBLIC KEY-----
#       -----END PUBLIC KEY-----
#   - Do not paste this key interactively; this script converts the PEM into the
#     escaped newline format expected by the installer.
#
# Behavior:
#   - Exports KEY_ARN, BUCKET_NAME, CALLBACK_URL, PAIRING_TOKEN, and
#     CALLBACK_PUBLIC_KEY, then runs install.sh with sudo --preserve-env.
#   - If /opt/fireblocks already exists, passes --force to install.sh.
#   - If a previous Nitro Enclaves allocation has offlined host CPUs, releases
#     the existing allocator/enclave before rerunning install.sh.
#   - After install.sh finishes, rewrites /opt/fireblocks/env.txt into a minimal
#     shell-quoted format so the enclave-side parser can read values containing
#     spaces and backslashes, especially CALLBACK_PUBLIC_KEY.
#   - Restarts cosigner-env-export.service and cosigner after normalizing env.txt.
#
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${1:-$BASE_DIR/e2e-t2.txt}"
PUBLIC_KEY_FILE="${2:-$BASE_DIR/callback_public.pem}"
INSTALL_SCRIPT="${3:-$BASE_DIR/install.sh}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: input file not found: $INPUT_FILE" >&2
  exit 1
fi

if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
  echo "Error: public key file not found: $PUBLIC_KEY_FILE" >&2
  exit 1
fi

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
  echo "Error: install script not found: $INSTALL_SCRIPT" >&2
  exit 1
fi

# Read first 4 non-empty lines in order:
# 1) KEY_ARN
# 2) BUCKET_NAME
# 3) CALLBACK_URL
# 4) PAIRING_TOKEN
mapfile -t cfg_lines < <(awk 'NF { print }' "$INPUT_FILE")
if [[ "${#cfg_lines[@]}" -lt 4 ]]; then
  echo "Error: $INPUT_FILE must contain at least 4 non-empty lines:" >&2
  echo "  1) KEY_ARN" >&2
  echo "  2) BUCKET_NAME" >&2
  echo "  3) CALLBACK_URL" >&2
  echo "  4) PAIRING_TOKEN" >&2
  exit 1
fi

export KEY_ARN="${cfg_lines[0]}"
export BUCKET_NAME="${cfg_lines[1]}"
export CALLBACK_URL="${cfg_lines[2]}"
export PAIRING_TOKEN="${cfg_lines[3]}"

# Validate PEM public key.
if ! openssl rsa -pubin -in "$PUBLIC_KEY_FILE" -noout >/dev/null 2>&1; then
  echo "Error: invalid public key format: $PUBLIC_KEY_FILE" >&2
  exit 1
fi

# Convert PEM file to literal '\n' style expected by the installer env var.
export CALLBACK_PUBLIC_KEY
CALLBACK_PUBLIC_KEY="$(awk '{ printf "%s\\\\n", $0 }' "$PUBLIC_KEY_FILE")"


# If a previous install enabled Nitro Enclaves allocator, host-visible CPUs may
# be reduced before this wrapper reaches install_deps.sh. Release them for reruns.
TOTAL_CPUS_ALL="$(getconf _NPROCESSORS_CONF)"
TOTAL_CPUS_VISIBLE="$(nproc)"


if [[ "$TOTAL_CPUS_ALL" -ge 4 && "$TOTAL_CPUS_VISIBLE" -lt 4 ]]; then
  
  echo "Detected host CPUs reserved by Nitro Enclaves allocator. Releasing them before rerun..."
  sudo systemctl stop cosigner cosigner-networking cosigner-logging cosigner-env-export 2>/dev/null || true
  sudo nitro-cli terminate-enclave --enclave-name cosigner 2>/dev/null || true
  sudo systemctl disable --now nitro-enclaves-allocator.service 2>/dev/null || true
  for cpu_online in /sys/devices/system/cpu/cpu*/online; do
    echo 1 | sudo tee "$cpu_online" >/dev/null || true
  done
fi

# Preflight checks mirroring install_deps.sh requirements.
TOTAL_CPUS="$(nproc)"
if [[ "$TOTAL_CPUS" -lt 4 ]]; then
  echo "Error: Not enough CPUs for enclave allocation. Detected $TOTAL_CPUS CPUs, need at least 4." >&2
  echo "Hint: use an instance type with >=4 vCPUs, then rerun this script." >&2
  exit 1
fi

TOTAL_MEM_MIB="$(awk '/MemTotal/ { mem=$2/1024; p=1; while (p < mem) p*=2; print p }' /proc/meminfo)"
ENCLAVE_MEM="$((TOTAL_MEM_MIB / 2))"
if [[ "$ENCLAVE_MEM" -lt 4096 ]]; then
  echo "Error: Not enough memory for enclave allocation. Detected ${TOTAL_MEM_MIB} MiB total, need at least 8192 MiB." >&2
  echo "Hint: use an instance type with >=8 GiB RAM, then rerun this script." >&2
  exit 1
fi

# Optional pairing-token expiry check.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$PAIRING_TOKEN" <<'PY'
import base64
import json
import sys
import time
import datetime

token = sys.argv[1]
try:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("token is not JWT format")
    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload))
    exp = int(claims["exp"])
except Exception as exc:
    print(f"Error: could not parse PAIRING_TOKEN: {exc}", file=sys.stderr)
    sys.exit(1)

now = int(time.time())
if exp <= now:
    print(
        f"Error: PAIRING_TOKEN is expired (exp={datetime.datetime.utcfromtimestamp(exp).isoformat()}Z)",
        file=sys.stderr,
    )
    sys.exit(1)

remaining = exp - now
print(f"PAIRING_TOKEN is valid for {remaining} more seconds.")
PY
fi

echo "Starting install with values from:"
echo "  - $INPUT_FILE"
echo "  - $PUBLIC_KEY_FILE"

INSTALL_ARGS=()
if [[ -d "/opt/fireblocks" ]] && [[ -n "$(ls -A /opt/fireblocks 2>/dev/null)" ]]; then
  echo "Detected existing /opt/fireblocks. Re-running installer with --force."
  INSTALL_ARGS+=(--force)
fi

if [[ "$EUID" -eq 0 ]]; then
  "$INSTALL_SCRIPT" "${INSTALL_ARGS[@]}"
else
  sudo --preserve-env=KEY_ARN,BUCKET_NAME,CALLBACK_URL,PAIRING_TOKEN,CALLBACK_PUBLIC_KEY "$INSTALL_SCRIPT" "${INSTALL_ARGS[@]}"
fi

echo "Normalizing /opt/fireblocks/env.txt for enclave env parser..."
tmp_env_file="$(mktemp)"
python3 - "$tmp_env_file" <<'PY'
import os
import shlex
import sys

path = sys.argv[1]
keys = [
    "KEY_ARN",
    "BUCKET_NAME",
    "PAIRING_TOKEN",
    "CALLBACK_URL",
    "CALLBACK_PUBLIC_KEY",
    "CALLBACK_CERT",
]

with open(path, "w", encoding="utf-8") as f:
    for key in keys:
        value = os.environ.get(key)
        if value is None:
            continue
        f.write(f"{key}={shlex.quote(value)}\n")
PY
sudo install -m 0644 -o root -g root "$tmp_env_file" /opt/fireblocks/env.txt
rm -f "$tmp_env_file"


echo "Restarting cosigner services with normalized environment..."
sudo systemctl restart cosigner-env-export.service cosigner

