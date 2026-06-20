#!/bin/bash

# Load deployment configuration from .env and common.json.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/load-config.sh"

_LOAD_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_LOAD_CONFIG_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
COMMON_CONFIG="${REPO_ROOT}/infrastructure/parameters/common.json"

# Defaults (used when .env is missing)
PROJECT_NAME="${PROJECT_NAME:-e2e-monitor-cbh}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-${REGION:-ap-northeast-1}}"
AWS_PROFILE="${AWS_PROFILE:-}"

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    REGION="${AWS_REGION:-${REGION:-ap-northeast-1}}"
fi

if [ -f "$COMMON_CONFIG" ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required to parse common.json. Please install jq." >&2
        return 1 2>/dev/null || exit 1
    fi

    FIREBLOCKS_SAAS_ENVIRONMENT="${FIREBLOCKS_SAAS_ENVIRONMENT:-$(jq -r '.FireblocksSaaSEnvironment // "global"' "$COMMON_CONFIG")}"
    VPC_CIDR="${VPC_CIDR:-$(jq -r '.NetworkConfig.VpcCidr' "$COMMON_CONFIG")}"
    PUBLIC_SUBNET_CIDR="${PUBLIC_SUBNET_CIDR:-$(jq -r '.NetworkConfig.PublicSubnetCidr' "$COMMON_CONFIG")}"
    PRIVATE_SUBNET_CIDR="${PRIVATE_SUBNET_CIDR:-$(jq -r '.NetworkConfig.PrivateSubnetCidr' "$COMMON_CONFIG")}"
else
    FIREBLOCKS_SAAS_ENVIRONMENT="${FIREBLOCKS_SAAS_ENVIRONMENT:-global}"
    VPC_CIDR="${VPC_CIDR:-10.0.0.0/16}"
    PUBLIC_SUBNET_CIDR="${PUBLIC_SUBNET_CIDR:-10.0.0.0/20}"
    PRIVATE_SUBNET_CIDR="${PRIVATE_SUBNET_CIDR:-10.0.128.0/20}"
fi

export PROJECT_NAME ENVIRONMENT REGION AWS_PROFILE
export FIREBLOCKS_SAAS_ENVIRONMENT VPC_CIDR PUBLIC_SUBNET_CIDR PRIVATE_SUBNET_CIDR
export REPO_ROOT ENV_FILE COMMON_CONFIG
