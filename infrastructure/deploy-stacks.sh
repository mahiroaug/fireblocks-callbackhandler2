#!/bin/bash

# Fireblocks Callback Handler - Multi-Stack Deployment Script
# This script deploys all CloudFormation stacks in the correct order

set -e

# Configuration
REGION="ap-northeast-1"
PROFILE="dev_mtools"
ENVIRONMENT="dev"
STACK_PREFIX="fireblocks-callback-handler"

# Stack Names
FOUNDATION_STACK="${STACK_PREFIX}-foundation-${ENVIRONMENT}"
SECURITY_STACK="${STACK_PREFIX}-security-${ENVIRONMENT}"
DNS_STACK="${STACK_PREFIX}-dns-${ENVIRONMENT}"
CALLBACK_HANDLER_STACK="${STACK_PREFIX}-callback-handler-${ENVIRONMENT}"
COSIGNER_STACK="${STACK_PREFIX}-cosigner-${ENVIRONMENT}"

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

# Function to check if stack exists
stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" --profile "$PROFILE" &>/dev/null
}

# Function to wait for stack operation completion
wait_for_stack() {
    local stack_name=$1
    local operation=$2
    print_status "$BLUE" "Waiting for stack $stack_name to $operation..."
    aws cloudformation wait stack-$operation-complete --stack-name "$stack_name" --region "$REGION" --profile "$PROFILE"
}

# Function to deploy or update stack
deploy_stack() {
    local stack_name=$1
    local template_file=$2
    local parameters_file=$3
    local operation=""
    
    if stack_exists "$stack_name"; then
        print_status "$YELLOW" "Updating existing stack: $stack_name"
        operation="update"
        
        # Check if update is needed
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body file://"$template_file" \
            --parameters file://"$parameters_file" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$REGION" \
            --profile "$PROFILE" 2>/dev/null || {
            if [ $? -eq 255 ]; then
                print_status "$YELLOW" "No updates required for $stack_name"
                return 0
            fi
            exit 1
        }
    else
        print_status "$GREEN" "Creating new stack: $stack_name"
        operation="create"
        
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body file://"$template_file" \
            --parameters file://"$parameters_file" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$REGION" \
            --profile "$PROFILE"
    fi
    
    wait_for_stack "$stack_name" "$operation"
    print_status "$GREEN" "Stack $stack_name $operation completed successfully!"
}

# Function to delete stack
delete_stack() {
    local stack_name=$1
    
    if stack_exists "$stack_name"; then
        print_status "$RED" "Deleting stack: $stack_name"
        aws cloudformation delete-stack \
            --stack-name "$stack_name" \
            --region "$REGION" \
            --profile "$PROFILE"
        
        wait_for_stack "$stack_name" "delete"
        print_status "$GREEN" "Stack $stack_name deleted successfully!"
    else
        print_status "$YELLOW" "Stack $stack_name does not exist"
    fi
}

# Function to show stack status
show_stack_status() {
    local stack_name=$1
    
    if stack_exists "$stack_name"; then
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$REGION" \
            --profile "$PROFILE" \
            --query 'Stacks[0].StackStatus' \
            --output text)
        print_status "$BLUE" "Stack $stack_name: $status"
    else
        print_status "$YELLOW" "Stack $stack_name: NOT_EXISTS"
    fi
}

# Function to create parameter files
create_parameter_files() {
    local env_dir="infrastructure/parameters/${ENVIRONMENT}"
    mkdir -p "$env_dir"
    
    # Foundation Stack Parameters
    cat > "$env_dir/foundation.json" << EOF
[
    {
        "ParameterKey": "VpcCIDR",
        "ParameterValue": "10.0.0.0/16"
    },
    {
        "ParameterKey": "PublicSubnetCIDR",
        "ParameterValue": "10.0.0.0/20"
    },
    {
        "ParameterKey": "PrivateSubnetCIDR",
        "ParameterValue": "10.0.128.0/20"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${ENVIRONMENT}"
    }
]
EOF

    # Security Stack Parameters
    cat > "$env_dir/security.json" << EOF
[
    {
        "ParameterKey": "FoundationStackName",
        "ParameterValue": "${FOUNDATION_STACK}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${ENVIRONMENT}"
    }
]
EOF

    # DNS Stack Parameters
    cat > "$env_dir/dns.json" << EOF
[
    {
        "ParameterKey": "FoundationStackName",
        "ParameterValue": "${FOUNDATION_STACK}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${ENVIRONMENT}"
    },
    {
        "ParameterKey": "DomainName",
        "ParameterValue": "callback-handler.internal"
    }
]
EOF

    # Callback Handler Stack Parameters
    cat > "$env_dir/callback-handler.json" << EOF
[
    {
        "ParameterKey": "FoundationStackName",
        "ParameterValue": "${FOUNDATION_STACK}"
    },
    {
        "ParameterKey": "SecurityStackName",
        "ParameterValue": "${SECURITY_STACK}"
    },
    {
        "ParameterKey": "DNSStackName",
        "ParameterValue": "${DNS_STACK}"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "${ENVIRONMENT}"
    },
    {
        "ParameterKey": "ContainerImage",
        "ParameterValue": "nginx:latest"
    },
    {
        "ParameterKey": "SSLCertificateArn",
        "ParameterValue": "arn:aws:acm:${REGION}:${AWS::AccountId}:certificate/REPLACE_ME"
    }
]
EOF

    # Cosigner Stack Parameters
    cat > "$env_dir/cosigner.json" << EOF
[
    {
        "ParameterKey": "FoundationStackName",
        "ParameterValue": "${FOUNDATION_STACK}"
    },
    {
        "ParameterKey": "SecurityStackName",
        "ParameterValue": "${SECURITY_STACK}"
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
        "ParameterKey": "CosignerPairingToken",
        "ParameterValue": "REPLACE_WITH_PAIRING_TOKEN"
    },
    {
        "ParameterKey": "CosignerInstallationScript",
        "ParameterValue": "REPLACE_WITH_INSTALLATION_SCRIPT_URL"
    }
]
EOF

    print_status "$GREEN" "Parameter files created in $env_dir"
}

# Function to show help
show_help() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  deploy-all        Deploy all stacks in correct order"
    echo "  deploy-foundation Deploy foundation stack only"
    echo "  deploy-security   Deploy security stack only"
    echo "  deploy-dns        Deploy DNS stack only"
    echo "  deploy-callback   Deploy callback handler stack only"
    echo "  deploy-cosigner   Deploy cosigner stack only"
    echo "  delete-all        Delete all stacks in reverse order"
    echo "  status            Show status of all stacks"
    echo "  create-params     Create parameter files"
    echo "  help              Show this help message"
    echo
    echo "Options:"
    echo "  -e, --environment Environment (dev/prod, default: dev)"
    echo "  -r, --region      AWS region (default: ap-northeast-1)"
    echo "  -p, --profile     AWS profile (default: dev_mtools)"
    echo
    echo "Examples:"
    echo "  $0 deploy-all"
    echo "  $0 deploy-all -e prod"
    echo "  $0 status"
    echo "  $0 delete-all"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            COMMAND="$1"
            shift
            ;;
    esac
done

# Update stack names with new environment
FOUNDATION_STACK="${STACK_PREFIX}-foundation-${ENVIRONMENT}"
SECURITY_STACK="${STACK_PREFIX}-security-${ENVIRONMENT}"
DNS_STACK="${STACK_PREFIX}-dns-${ENVIRONMENT}"
CALLBACK_HANDLER_STACK="${STACK_PREFIX}-callback-handler-${ENVIRONMENT}"
COSIGNER_STACK="${STACK_PREFIX}-cosigner-${ENVIRONMENT}"

# Main script logic
case "$COMMAND" in
    deploy-all)
        print_status "$GREEN" "Starting deployment of all stacks for environment: $ENVIRONMENT"
        create_parameter_files
        
        # Deploy stacks in dependency order
        deploy_stack "$FOUNDATION_STACK" "infrastructure/stacks/01-foundation.yaml" "infrastructure/parameters/${ENVIRONMENT}/foundation.json"
        deploy_stack "$SECURITY_STACK" "infrastructure/stacks/02-security.yaml" "infrastructure/parameters/${ENVIRONMENT}/security.json"
        deploy_stack "$DNS_STACK" "infrastructure/stacks/03-dns.yaml" "infrastructure/parameters/${ENVIRONMENT}/dns.json"
        deploy_stack "$CALLBACK_HANDLER_STACK" "infrastructure/stacks/04-callback-handler.yaml" "infrastructure/parameters/${ENVIRONMENT}/callback-handler.json"
        deploy_stack "$COSIGNER_STACK" "infrastructure/stacks/05-cosigner.yaml" "infrastructure/parameters/${ENVIRONMENT}/cosigner.json"
        
        print_status "$GREEN" "All stacks deployed successfully!"
        ;;
    
    deploy-foundation)
        create_parameter_files
        deploy_stack "$FOUNDATION_STACK" "infrastructure/stacks/01-foundation.yaml" "infrastructure/parameters/${ENVIRONMENT}/foundation.json"
        ;;
    
    deploy-security)
        create_parameter_files
        deploy_stack "$SECURITY_STACK" "infrastructure/stacks/02-security.yaml" "infrastructure/parameters/${ENVIRONMENT}/security.json"
        ;;
    
    deploy-dns)
        create_parameter_files
        deploy_stack "$DNS_STACK" "infrastructure/stacks/03-dns.yaml" "infrastructure/parameters/${ENVIRONMENT}/dns.json"
        ;;
    
    deploy-callback)
        create_parameter_files
        deploy_stack "$CALLBACK_HANDLER_STACK" "infrastructure/stacks/04-callback-handler.yaml" "infrastructure/parameters/${ENVIRONMENT}/callback-handler.json"
        ;;
    
    deploy-cosigner)
        create_parameter_files
        deploy_stack "$COSIGNER_STACK" "infrastructure/stacks/05-cosigner.yaml" "infrastructure/parameters/${ENVIRONMENT}/cosigner.json"
        ;;
    
    delete-all)
        print_status "$RED" "Deleting all stacks in reverse order..."
        delete_stack "$COSIGNER_STACK"
        delete_stack "$CALLBACK_HANDLER_STACK"
        delete_stack "$DNS_STACK"
        delete_stack "$SECURITY_STACK"
        delete_stack "$FOUNDATION_STACK"
        print_status "$GREEN" "All stacks deleted successfully!"
        ;;
    
    status)
        print_status "$BLUE" "Stack Status for environment: $ENVIRONMENT"
        show_stack_status "$FOUNDATION_STACK"
        show_stack_status "$SECURITY_STACK"
        show_stack_status "$DNS_STACK"
        show_stack_status "$CALLBACK_HANDLER_STACK"
        show_stack_status "$COSIGNER_STACK"
        ;;
    
    create-params)
        create_parameter_files
        ;;
    
    help|--help|-h)
        show_help
        ;;
    
    *)
        print_status "$RED" "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac 