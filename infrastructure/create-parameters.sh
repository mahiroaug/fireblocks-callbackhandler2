#!/bin/bash

# Fireblocks Callback Handler - Parameter Files Creation Script
# Creates CloudFormation parameter files from .env and common.json
# Usage: ./create-parameters.sh [environment]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

CLI_ENVIRONMENT=""
if [ $# -eq 1 ]; then
    CLI_ENVIRONMENT="$1"
fi

# shellcheck source=load-config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/load-config.sh"

if [ -n "$CLI_ENVIRONMENT" ]; then
    ENVIRONMENT="$CLI_ENVIRONMENT"
fi

if [ -f "$ENV_FILE" ]; then
    print_status "$GREEN" "🚀 Creating parameter files for environment: $ENVIRONMENT"
    print_status "$BLUE" "📝 Project/Environment from: $ENV_FILE"
else
    print_status "$YELLOW" "🚀 Creating parameter files for environment: $ENVIRONMENT"
    print_status "$YELLOW" "📝 .env not found; using defaults (copy .env.example to .env)"
fi
print_status "$BLUE" "📝 Network/Fireblocks settings from: $COMMON_CONFIG"

# Create environment directory
env_dir="${REPO_ROOT}/infrastructure/parameters/${ENVIRONMENT}"
mkdir -p "$env_dir"

print_status "$BLUE" "📁 Creating parameter files in: $env_dir"

# Foundation Stack Parameters
cat > "$env_dir/foundation.json" << EOF
[
    {
        "ParameterKey": "ProjectName",
        "ParameterValue": "${PROJECT_NAME}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${ENVIRONMENT}"
    },
    {
        "ParameterKey": "VpcCIDR",
        "ParameterValue": "${VPC_CIDR}"
    },
    {
        "ParameterKey": "PublicSubnetCIDR",
        "ParameterValue": "${PUBLIC_SUBNET_CIDR}"
    },
    {
        "ParameterKey": "PrivateSubnetCIDR",
        "ParameterValue": "${PRIVATE_SUBNET_CIDR}"
    }
]
EOF

# Security Stack Parameters - preserve existing SSL certificate ARN if exists
existing_ssl_cert_arn=""
if [ -f "$env_dir/security.json" ]; then
    existing_ssl_cert_arn=$(jq -r '.[] | select(.ParameterKey=="SSLCertificateArn") | .ParameterValue' "$env_dir/security.json")
fi

# If no existing SSL cert ARN, use placeholder
if [ -z "$existing_ssl_cert_arn" ] || [ "$existing_ssl_cert_arn" == "null" ]; then
    existing_ssl_cert_arn="PLACEHOLDER_SSL_CERTIFICATE_ARN"
fi

cat > "$env_dir/security.json" << EOF
[
    {
        "ParameterKey": "ProjectName",
        "ParameterValue": "${PROJECT_NAME}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${ENVIRONMENT}"
    },
    {
        "ParameterKey": "FireblocksSaaSEnvironment",
        "ParameterValue": "${FIREBLOCKS_SAAS_ENVIRONMENT}"
    }
]
EOF

# Lambda Callback Stack Parameters (template)
cat > "$env_dir/lambda-callback.json" << EOF
[
    {
        "ParameterKey": "ProjectName",
        "ParameterValue": "${PROJECT_NAME}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${ENVIRONMENT}"
    },
    {
        "ParameterKey": "ContainerImage",
        "ParameterValue": "PLACEHOLDER_CONTAINER_IMAGE"
    }
]
EOF

# CodeBuild Stack Parameters
cat > "$env_dir/codebuild.json" << EOF
[
    {
        "ParameterKey": "ProjectName",
        "ParameterValue": "${PROJECT_NAME}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${ENVIRONMENT}"
    }
]
EOF

# Cosigner Stack Parameters
cat > "$env_dir/cosigner.json" << EOF
[
    {
        "ParameterKey": "ProjectName",
        "ParameterValue": "${PROJECT_NAME}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${ENVIRONMENT}"
    },
    {
        "ParameterKey": "InstanceType",
        "ParameterValue": "c5.xlarge"
    },
    {
        "ParameterKey": "EbsVolumeSize",
        "ParameterValue": "30"
    },
    {
        "ParameterKey": "KeyPairName",
        "ParameterValue": "PLACEHOLDER_KEY_PAIR_NAME"
    },
    {
        "ParameterKey": "CosignerAppLogGroupName",
        "ParameterValue": ""
    },
    {
        "ParameterKey": "CosignerLogRetentionDays",
        "ParameterValue": "90"
    },
    {
        "ParameterKey": "CosignerAppLogKmsKeyArn",
        "ParameterValue": ""
    },
    {
        "ParameterKey": "CosignerAlarmNotificationEmail",
        "ParameterValue": ""
    },
    {
        "ParameterKey": "CosignerSnsKmsKeyArn",
        "ParameterValue": ""
    }
]
EOF

print_status "$GREEN" "✅ Parameter files created successfully!"
print_status "$BLUE" "📁 Files created in: $env_dir"
print_status "$BLUE" "  - foundation.json"
print_status "$BLUE" "  - security.json"
print_status "$BLUE" "  - lambda-callback.json"
print_status "$BLUE" "  - codebuild.json"
print_status "$BLUE" "  - cosigner.json"

print_status "$YELLOW" ""
print_status "$YELLOW" "🔒 Next steps:"
print_status "$YELLOW" "1. Generate JWT certificates:"
print_status "$YELLOW" "   mkdir -p certs && cd certs"
print_status "$YELLOW" "   openssl genrsa -out callback_private.pem 2048"
print_status "$YELLOW" "   openssl rsa -in callback_private.pem -outform PEM -pubout -out callback_public.pem"
print_status "$YELLOW" ""
print_status "$YELLOW" "2. Place Cosigner public key:"
print_status "$YELLOW" "   # Get cosigner_public.pem from Fireblocks Console or Cosigner"
print_status "$YELLOW" "   # Place it in certs/cosigner_public.pem"
print_status "$YELLOW" ""
print_status "$YELLOW" "3. Run deployment (JWT certificates will be auto-registered):"
print_status "$YELLOW" "   ./infrastructure/deploy-automated.sh"
