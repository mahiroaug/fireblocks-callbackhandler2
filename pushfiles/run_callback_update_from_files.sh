#!/usr/bin/env bash
set -euo pipefail

# HOW TO USE
#
# Purpose:
#   Run `cosigner callback-update` non-interactively by reading the callback URL
#   and callback public key from local files.
#
# Default usage (on Cosigner EC2, after install):
#   cd /home/ec2-user
#   ./run_callback_update_from_files.sh
#
# Optional explicit paths:
#   ./run_callback_update_from_files.sh <input_file> <callback_public_key_pem>
#
# Defaults:
#   input_file              ./callback-update.txt
#   callback_public_key_pem ./callback_public.pem
#
# input_file format:
#   The first 1-2 non-empty lines are read in this exact order:
#
#     line 1: callback URL
#     line 2: callback authentication option (optional, default: 1)
#             1 = PUBLIC KEY
#             2 = certificate
#
#   Example:
#
#     https://example.execute-api.ap-northeast-1.amazonaws.com/prod/callback
#     1
#
# input_file constraints:
#   - Blank lines are ignored.
#   - Use the callback base URL ending in /callback (not /callback/v2/...).
#   - Option 2 (certificate) is not automated by this script; use option 1.
#
# callback_public_key_pem constraints:
#   - Must be a PEM public key accepted by:
#       openssl rsa -pubin -in <file> -noout
#   - Keep the standard markers:
#       -----BEGIN PUBLIC KEY-----
#       -----END PUBLIC KEY-----
#
# Behavior:
#   - Validates the PEM public key.
#   - Pipes callback URL, auth option, and PEM content into `cosigner callback-update`.
#   - Restarts cosigner after a successful update.

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${1:-$BASE_DIR/callback-update.txt}"
PUBLIC_KEY_FILE="${2:-$BASE_DIR/callback_public.pem}"

COSIGNER_BIN="${COSIGNER_BIN:-cosigner}"
if ! command -v "$COSIGNER_BIN" >/dev/null 2>&1; then
  if [[ -x /opt/fireblocks/cosigner ]]; then
    COSIGNER_BIN="/opt/fireblocks/cosigner"
  else
    echo "Error: cosigner command not found. Install Cosigner first or set COSIGNER_BIN." >&2
    exit 1
  fi
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: input file not found: $INPUT_FILE" >&2
  exit 1
fi

if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
  echo "Error: public key file not found: $PUBLIC_KEY_FILE" >&2
  exit 1
fi

mapfile -t cfg_lines < <(awk 'NF { print }' "$INPUT_FILE")
if [[ "${#cfg_lines[@]}" -lt 1 ]]; then
  echo "Error: $INPUT_FILE must contain at least 1 non-empty line (callback URL)." >&2
  exit 1
fi

CALLBACK_URL="${cfg_lines[0]}"
AUTH_OPTION="${cfg_lines[1]:-1}"

if [[ "$AUTH_OPTION" != "1" && "$AUTH_OPTION" != "2" ]]; then
  echo "Error: auth option must be 1 (PUBLIC KEY) or 2 (certificate), got: $AUTH_OPTION" >&2
  exit 1
fi

if [[ "$AUTH_OPTION" == "2" ]]; then
  echo "Error: auth option 2 (certificate) is not supported by this script." >&2
  echo "Use interactive: sudo $COSIGNER_BIN callback-update" >&2
  exit 1
fi

if ! openssl rsa -pubin -in "$PUBLIC_KEY_FILE" -noout >/dev/null 2>&1; then
  echo "Error: invalid public key format: $PUBLIC_KEY_FILE" >&2
  exit 1
fi

echo "Running callback-update with values from:"
echo "  - $INPUT_FILE"
echo "  - $PUBLIC_KEY_FILE"
echo "  - callback URL: $CALLBACK_URL"
echo "  - auth option: $AUTH_OPTION (PUBLIC KEY)"

run_callback_update() {
  {
    printf '%s\n' "$CALLBACK_URL"
    printf '%s\n' "$AUTH_OPTION"
    cat "$PUBLIC_KEY_FILE"
  } | "$@"
}

if [[ "$EUID" -eq 0 ]]; then
  run_callback_update "$COSIGNER_BIN" callback-update
else
  run_callback_update sudo "$COSIGNER_BIN" callback-update
fi

echo "Restarting cosigner..."
if [[ "$EUID" -eq 0 ]]; then
  systemctl restart cosigner-env-export.service cosigner
else
  sudo systemctl restart cosigner-env-export.service cosigner
fi

echo "Callback configuration updated."
