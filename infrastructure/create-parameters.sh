#!/bin/bash

# Fireblocks Callback Handler - Parameter Files Creation Script
# This script creates parameter files from common.json before deployment
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

# Default environment
ENVIRONMENT="dev"

# Parse command line arguments
if [ $# -eq 1 ]; then
    ENVIRONMENT="$1"
fi

# Configuration
COMMON_CONFIG="infrastructure/parameters/common.json"

# Check if common.json exists
if [ ! -f "$COMMON_CONFIG" ]; then
    print_status "$RED" "❌ common.json not found at $COMMON_CONFIG"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_status "$RED" "❌ jq is required. Please install jq."
    exit 1
fi

print_status "$GREEN" "🚀 Creating parameter files for environment: $ENVIRONMENT"
print_status "$BLUE" "📝 Reading configuration from: $COMMON_CONFIG"

# Load values from common.json
project_name=$(jq -r '.ProjectName' "$COMMON_CONFIG")
environment=$(jq -r '.Environment' "$COMMON_CONFIG")
region=$(jq -r '.Region' "$COMMON_CONFIG")
vpc_cidr=$(jq -r '.NetworkConfig.VpcCidr' "$COMMON_CONFIG")
public_subnet_cidr=$(jq -r '.NetworkConfig.PublicSubnetCidr' "$COMMON_CONFIG")
private_subnet_cidr=$(jq -r '.NetworkConfig.PrivateSubnetCidr' "$COMMON_CONFIG")

# Override environment if provided as argument
if [ "$ENVIRONMENT" != "dev" ]; then
    environment="$ENVIRONMENT"
fi

# Create environment directory
env_dir="infrastructure/parameters/${environment}"
mkdir -p "$env_dir"

print_status "$BLUE" "📁 Creating parameter files in: $env_dir"

# Foundation Stack Parameters
cat > "$env_dir/foundation.json" << EOF
[
    {
        "ParameterKey": "ProjectName",
        "ParameterValue": "${project_name}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${environment}"
    },
    {
        "ParameterKey": "VpcCIDR",
        "ParameterValue": "${vpc_cidr}"
    },
    {
        "ParameterKey": "PublicSubnetCIDR",
        "ParameterValue": "${public_subnet_cidr}"
    },
    {
        "ParameterKey": "PrivateSubnetCIDR",
        "ParameterValue": "${private_subnet_cidr}"
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
        "ParameterValue": "${project_name}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${environment}"
    }
]
EOF

# Lambda Callback Stack Parameters (template)
cat > "$env_dir/lambda-callback.json" << EOF
[
    {
        "ParameterKey": "ProjectName",
        "ParameterValue": "${project_name}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${environment}"
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
        "ParameterValue": "${project_name}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${environment}"
    }
]
EOF

# Cosigner Stack Parameters
cat > "$env_dir/cosigner.json" << EOF
[
    {
        "ParameterKey": "ProjectName",
        "ParameterValue": "${project_name}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${environment}"
    },
    {
        "ParameterKey": "InstanceType",
        "ParameterValue": "c5.xlarge"
    },
    {
        "ParameterKey": "KeyPairName",
        "ParameterValue": "PLACEHOLDER_KEY_PAIR_NAME"
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
print_status "$YELLOW" "   ./infrastructure/deploy-automated.sh -p <aws_profile>" 