#!/bin/bash

# Fireblocks Callback Handler - Automated Deployment Script
# This script automates the entire deployment process including SSL certificate generation,
# Docker image building, and infrastructure deployment

set -e

# Disable AWS CLI pager to prevent interactive prompts
export AWS_PAGER=""

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

# Configuration
REGION="ap-northeast-1"
PROFILE="default"
ENVIRONMENT="dev"
FROM_STACK=""
SKIP_STACKS=""
DRY_RUN=false

# Load configuration from common.json
COMMON_CONFIG="infrastructure/parameters/common.json"
if [ -f "$COMMON_CONFIG" ]; then
    if ! command -v jq &> /dev/null; then
        print_status "$RED" "Error: jq is required to parse common.json. Please install jq."
        exit 1
    fi
    
    PROJECT_NAME=$(jq -r '.ProjectName' "$COMMON_CONFIG")
    REGION=$(jq -r '.Region' "$COMMON_CONFIG")
    ENVIRONMENT=$(jq -r '.Environment' "$COMMON_CONFIG")
    
    print_status "$GREEN" "Configuration loaded from common.json"
    print_status "$BLUE" "Project: $PROJECT_NAME, Region: $REGION, Environment: $ENVIRONMENT"
else
    PROJECT_NAME="e2e-monitor-cbh"
    print_status "$YELLOW" "Warning: common.json not found, using default values"
fi

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
        --from-stack)
            FROM_STACK="$2"
            shift 2
            ;;
        --skip-stacks)
            SKIP_STACKS="$2"
            shift 2
            ;;
        --only-stacks)
            ONLY_STACKS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --status)
            SHOW_STATUS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -e, --environment Environment (dev, staging, prod)"
            echo "  -r, --region      AWS region"
            echo "  -p, --profile     AWS profile"
              echo "  --from-stack      Start deployment from specific stack (foundation, security, dns, codebuild, callback, cosigner)"
  echo "  --skip-stacks     Skip specific stacks (comma-separated: foundation,security,dns,codebuild,callback,cosigner)"
            echo "  --only-stacks     Run only specified stacks (comma-separated), overrides --from/--skip"
            echo "  --dry-run         Show what would be deployed without actually deploying"
            echo "  --status          Show current status of all stacks"
            echo "  -h, --help        Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 -p dev_profile                    # Full deployment"
            echo "  $0 -p dev_profile --status           # Check stack status"
            echo "  $0 -p dev_profile --dry-run          # Preview deployment"
            echo "  $0 -p dev_profile --from-stack dns   # Start from DNS stack"
            echo "  $0 -p dev_profile --skip-stacks cosigner  # Skip cosigner stack"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_status "$BLUE" "Starting automated deployment..."
print_status "$BLUE" "Profile: $PROFILE, Region: $REGION, Environment: $ENVIRONMENT"

# Stack Names (with numbering for clear deployment order)

FOUNDATION_STACK="${PROJECT_NAME}-01-foundation-${ENVIRONMENT}"
SECURITY_STACK="${PROJECT_NAME}-02-security-${ENVIRONMENT}"
DNS_STACK="${PROJECT_NAME}-03-dns-${ENVIRONMENT}"
CODEBUILD_STACK="${PROJECT_NAME}-04-codebuild-${ENVIRONMENT}"
CALLBACK_HANDLER_STACK="${PROJECT_NAME}-05-callback-handler-${ENVIRONMENT}"
COSIGNER_STACK="${PROJECT_NAME}-06-cosigner-${ENVIRONMENT}"

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$PROFILE" --no-paginate)

# Function to wait for stack operation completion
wait_for_stack() {
    local stack_name=$1
    local operation=$2
    print_status "$BLUE" "Waiting for stack $stack_name to $operation..."
    aws cloudformation wait stack-$operation-complete --stack-name "$stack_name" --region "$REGION" --profile "$PROFILE" --no-paginate
}

# Function to check if stack exists
stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" --profile "$PROFILE" --no-paginate &>/dev/null
}

# Function to get stack status
get_stack_status() {
    local stack_name=$1
    if stack_exists "$stack_name"; then
        aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$REGION" \
            --profile "$PROFILE" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            --no-paginate
    else
        echo "NOT_FOUND"
    fi
}

# Function to show stack status
show_stack_status() {
    local stack_name=$1
    local display_name=$2
    local status=$(get_stack_status "$stack_name")
    
    case "$status" in
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            print_status "$GREEN" "  ✅ $display_name: $status"
            print_status "$GREEN" "      Stack: $stack_name"
            ;;
        "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS")
            print_status "$YELLOW" "  🔄 $display_name: $status"
            print_status "$YELLOW" "      Stack: $stack_name"
            ;;
        "CREATE_FAILED"|"UPDATE_FAILED"|"ROLLBACK_COMPLETE"|"ROLLBACK_IN_PROGRESS")
            print_status "$RED" "  ❌ $display_name: $status"
            print_status "$RED" "      Stack: $stack_name"
            ;;
        "NOT_FOUND")
            print_status "$YELLOW" "  ⚪ $display_name: Not deployed"
            print_status "$YELLOW" "      Stack: $stack_name"
            ;;
        *)
            print_status "$YELLOW" "  ⚠️ $display_name: $status"
            print_status "$YELLOW" "      Stack: $stack_name"
            ;;
    esac
}

# Function to show all stacks status
show_all_stacks_status() {
    print_status "$BLUE" "📊 Stack Status Summary (Environment: $ENVIRONMENT)"
    print_status "$BLUE" "================================================="
    

    show_stack_status "$FOUNDATION_STACK" "1️⃣ Foundation (VPC, Subnets)"
    show_stack_status "$SECURITY_STACK" "2️⃣ Security (IAM, Security Groups)"
    show_stack_status "$DNS_STACK" "3️⃣ DNS (Private Hosted Zone)"
    show_stack_status "$CODEBUILD_STACK" "4️⃣ CodeBuild + ECR"
    show_stack_status "$CALLBACK_HANDLER_STACK" "5️⃣ Callback Handler (ALB, ECS)"
    show_stack_status "$COSIGNER_STACK" "6️⃣ Cosigner (EC2, Nitro Enclave)"
    
    print_status "$BLUE" "================================================="
}

# Function to check if stack should be skipped
should_skip_stack() {
    local stack_short_name=$1
    # if ONLY_STACKS is set, skip anything not in list
    if [ -n "$ONLY_STACKS" ]; then
        echo "$ONLY_STACKS" | tr ',' '\n' | grep -q "^$stack_short_name$"
        if [ $? -ne 0 ]; then
            return 0  # skip
        fi
        return 1      # do not skip
    fi
    if [ -n "$SKIP_STACKS" ]; then
        echo "$SKIP_STACKS" | grep -q "$stack_short_name"
        return $?
    fi
    return 1
}

# Function to check if we should start from this stack
should_start_from_stack() {
    local stack_short_name=$1
    if [ -n "$FROM_STACK" ]; then
        [ "$FROM_STACK" == "$stack_short_name" ]
        return $?
    fi
    return 0
}

# Function to deploy stack
deploy_stack() {
    local stack_name=$1
    local template_file=$2
    local parameters_file=$3
    local stack_display_name=$4
    local operation=""
    
    if [ "$DRY_RUN" == "true" ]; then
        if stack_exists "$stack_name"; then
            print_status "$BLUE" "🔍 [DRY RUN] Would update: $stack_display_name"
            print_status "$BLUE" "    Template: $template_file"
            print_status "$BLUE" "    Parameters: $parameters_file"
        else
            print_status "$BLUE" "🔍 [DRY RUN] Would create: $stack_display_name"
            print_status "$BLUE" "    Template: $template_file"
            print_status "$BLUE" "    Parameters: $parameters_file"
        fi
        return 0
    fi
    
    if stack_exists "$stack_name"; then
        print_status "$YELLOW" "Updating existing stack: $stack_display_name"
        operation="update"
        
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body file://"$template_file" \
            --parameters file://"$parameters_file" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$REGION" \
            --profile "$PROFILE" \
            --no-paginate 2>/dev/null || {
            local exit_code=$?
            if [ $exit_code -eq 255 ]; then
                print_status "$YELLOW" "No updates required for $stack_display_name"
                return 0
            else
                print_status "$RED" "Failed to update $stack_display_name (exit code: $exit_code)"
                print_status "$RED" "Check AWS Console for detailed error information"
                return 1
            fi
        }
    else
        print_status "$GREEN" "Creating new stack: $stack_display_name"
        operation="create"
        
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body file://"$template_file" \
            --parameters file://"$parameters_file" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$REGION" \
            --profile "$PROFILE" \
            --no-paginate || {
            local exit_code=$?
            print_status "$RED" "Failed to create $stack_display_name (exit code: $exit_code)"
            print_status "$RED" "Check AWS Console for detailed error information"
            return 1
        }
    fi
    
    wait_for_stack "$stack_name" "$operation"
    
    # Check if stack deployment succeeded
    local final_status=$(get_stack_status "$stack_name")
    case "$final_status" in
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            print_status "$GREEN" "✅ $stack_display_name: Deployment successful"
            ;;
        *)
            print_status "$RED" "❌ $stack_display_name: Deployment failed with status: $final_status"
            return 1
            ;;
    esac
}

# Function to register JWT certificates to SSM Parameter Store
register_jwt_certificates() {
    print_status "$BLUE" "🔑 Checking for JWT certificates..."
    
    local callback_private_key="certs/callback_private.pem"
    local cosigner_public_key="certs/cosigner_public.pem"
    
    local callback_param_name="/${PROJECT_NAME}/${ENVIRONMENT}/jwt/callback-private-key"
    local cosigner_param_name="/${PROJECT_NAME}/${ENVIRONMENT}/jwt/cosigner-public-key"
    
    # Check if JWT certificate files exist
    if [ ! -f "$callback_private_key" ]; then
        print_status "$RED" "❌ JWT certificate not found: $callback_private_key"
        print_status "$RED" "Please generate JWT certificates first:"
        print_status "$YELLOW" "  mkdir -p certs && cd certs"
        print_status "$YELLOW" "  openssl genrsa -out callback_private.pem 2048"
        print_status "$YELLOW" "  openssl rsa -in callback_private.pem -outform PEM -pubout -out callback_public.pem"
        print_status "$YELLOW" "  # Place cosigner_public.pem from Fireblocks Cosigner"
        return 1
    fi
    
    if [ ! -f "$cosigner_public_key" ]; then
        print_status "$RED" "❌ Cosigner public key not found: $cosigner_public_key"
        print_status "$RED" "Please obtain cosigner_public.pem from Fireblocks Cosigner and place it in certs/"
        return 1
    fi
    
    print_status "$GREEN" "✅ JWT certificate files found"
    
    if [ "$DRY_RUN" == "true" ]; then
        print_status "$BLUE" "🔍 [DRY RUN] Would register JWT certificates to SSM Parameter Store:"
        print_status "$BLUE" "    - $callback_param_name"
        print_status "$BLUE" "    - $cosigner_param_name"
        return 0
    fi
    
    # Register callback private key
    print_status "$BLUE" "📦 Registering callback private key to SSM Parameter Store..."
    aws ssm put-parameter \
        --name "$callback_param_name" \
        --description "JWT Callback Handler Private Key" \
        --value "file://$callback_private_key" \
        --type "SecureString" \
        --overwrite \
        --region "$REGION" \
        --profile "$PROFILE" \
        --no-paginate || {
        print_status "$RED" "❌ Failed to register callback private key"
        return 1
    }
    print_status "$GREEN" "✅ Callback private key registered: $callback_param_name"
    
    # Register cosigner public key
    print_status "$BLUE" "📦 Registering cosigner public key to SSM Parameter Store..."
    aws ssm put-parameter \
        --name "$cosigner_param_name" \
        --description "JWT Cosigner Public Key" \
        --value "file://$cosigner_public_key" \
        --type "SecureString" \
        --overwrite \
        --region "$REGION" \
        --profile "$PROFILE" \
        --no-paginate || {
        print_status "$RED" "❌ Failed to register cosigner public key"
        return 1
    }
    print_status "$GREEN" "✅ Cosigner public key registered: $cosigner_param_name"
    
    print_status "$GREEN" "🎉 JWT certificates successfully registered to SSM Parameter Store"
}

# Parameter files are created using infrastructure/create-parameters.sh script

# Function to get stack output
get_stack_output() {
    local stack_name=$1
    local output_key=$2
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text \
        --no-paginate
}

# Main deployment flow
main() {
    # Handle status request
    if [ "$SHOW_STATUS" == "true" ]; then
        show_all_stacks_status
        return 0
    fi
    
    print_status "$GREEN" "🚀 Starting automated deployment process..."
    
    if [ "$DRY_RUN" == "true" ]; then
        print_status "$BLUE" "🔍 DRY RUN MODE - No actual deployment will occur"
    fi
    
    if [ -n "$FROM_STACK" ]; then
        print_status "$BLUE" "📍 Starting from stack: $FROM_STACK"
    fi
    
    if [ -n "$SKIP_STACKS" ]; then
        print_status "$BLUE" "⏭️ Skipping stacks: $SKIP_STACKS"
    fi
    
    # Step 1: Check parameter files exist
    print_status "$BLUE" "📝 Step 1: Checking parameter files..."
    if [ ! -d "infrastructure/parameters/${ENVIRONMENT}" ]; then
        print_status "$RED" "❌ Parameter directory not found: infrastructure/parameters/${ENVIRONMENT}"
        print_status "$RED" "    Please run: ./infrastructure/create-parameters.sh ${ENVIRONMENT}"
        return 1
    fi
    
    # Check if SSL Certificate ARN is set
    if [ -f "infrastructure/parameters/${ENVIRONMENT}/security.json" ]; then
        ssl_cert_arn=$(jq -r '.[] | select(.ParameterKey=="SSLCertificateArn") | .ParameterValue' "infrastructure/parameters/${ENVIRONMENT}/security.json")
        if [ "$ssl_cert_arn" == "PLACEHOLDER_SSL_CERTIFICATE_ARN" ]; then
            print_status "$RED" "❌ SSL Certificate ARN is still placeholder!"
            print_status "$RED" "    Please complete the SSL certificate setup:"
            print_status "$RED" "    1. Generate SSL certificates"
            print_status "$RED" "    2. Import to AWS Certificate Manager"
            print_status "$RED" "    3. Update SSLCertificateArn in infrastructure/parameters/${ENVIRONMENT}/security.json"
            return 1
        fi
        print_status "$GREEN" "✅ SSL Certificate ARN configured: $ssl_cert_arn"
    fi
    
    print_status "$GREEN" "✅ Parameter files found in infrastructure/parameters/${ENVIRONMENT}/"
    
    # Step 1a: Register JWT certificates to SSM Parameter Store
    print_status "$BLUE" "📝 Step 1a: Registering JWT certificates to SSM Parameter Store..."
    if ! register_jwt_certificates; then
        print_status "$RED" "❌ JWT certificate registration failed. Please generate certificates first."
        return 1
    fi
    
    # Initialize variables for cross-stack references
    local started=false
    local SSL_CERT_ARN=""
    local ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PROJECT_NAME}"
    
    # Step 2: SSL Certificate ARN is handled in parameters files
    print_status "$BLUE" "🔒 Step 2: SSL Certificate ARN will be taken from parameters file"
    print_status "$YELLOW" "⚠️  Make sure you have imported your SSL certificate to ACM first"
    print_status "$YELLOW" "   and updated the SSLCertificateArn parameter in the security stack parameters"
    
    # Step 2: Deploy Foundation Stack
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "foundation" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "foundation"; then
        print_status "$BLUE" "🏗️ Step 2: Deploying foundation stack..."
        if ! deploy_stack "$FOUNDATION_STACK" "infrastructure/stacks/01-foundation.yaml" "infrastructure/parameters/${ENVIRONMENT}/foundation.json" "Foundation (VPC, Subnets)"; then
            print_status "$RED" "❌ Foundation deployment failed. Stopping."
            return 1
        fi
    elif [ "$started" == "false" ]; then
        print_status "$YELLOW" "⏭️ Skipping Foundation stack (before start point)"
    else
        print_status "$YELLOW" "⏭️ Skipping Foundation stack (explicitly skipped)"
    fi
    
    # Step 3: Deploy Security Stack
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "security" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "security"; then
        print_status "$BLUE" "🔐 Step 3: Deploying security stack..."
        if ! deploy_stack "$SECURITY_STACK" "infrastructure/stacks/02-security.yaml" "infrastructure/parameters/${ENVIRONMENT}/security.json" "Security (IAM, Security Groups)"; then
            print_status "$RED" "❌ Security deployment failed. Stopping."
            return 1
        fi
    elif [ "$started" == "false" ]; then
        print_status "$YELLOW" "⏭️ Skipping Security stack (before start point)"
    else
        print_status "$YELLOW" "⏭️ Skipping Security stack (explicitly skipped)"
    fi
    
    # Step 4: Deploy DNS Stack
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "dns" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "dns"; then
        print_status "$BLUE" "🌐 Step 4: Deploying DNS stack..."
        if ! deploy_stack "$DNS_STACK" "infrastructure/stacks/03-dns.yaml" "infrastructure/parameters/${ENVIRONMENT}/dns.json" "DNS (Private Hosted Zone)"; then
            print_status "$RED" "❌ DNS deployment failed. Stopping."
            return 1
        fi
    elif [ "$started" == "false" ]; then
        print_status "$YELLOW" "⏭️ Skipping DNS stack (before start point)"
    else
        print_status "$YELLOW" "⏭️ Skipping DNS stack (explicitly skipped)"
    fi
    
    # Step 5: Deploy CodeBuild Stack (with integrated ECR)
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "codebuild" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "codebuild"; then
        print_status "$BLUE" "🔨 Step 5: Deploying CodeBuild automation (with ECR)..."
        
        # Update (overwrite) ECR Repository URI in codebuild.json every time
        if [ -f "infrastructure/parameters/${ENVIRONMENT}/codebuild.json" ]; then
            tmp_json=$(mktemp)
            jq --arg uri "${ECR_REPO_URI}" 'map(if .ParameterKey=="ECRRepositoryURI" then .ParameterValue=$uri else . end)' \
              "infrastructure/parameters/${ENVIRONMENT}/codebuild.json" > "$tmp_json" && \
              mv "$tmp_json" "infrastructure/parameters/${ENVIRONMENT}/codebuild.json"
            print_status "$GREEN" "✅ Set ECRRepositoryURI to $ECR_REPO_URI in codebuild.json"
        else
            print_status "$RED" "❌ Parameter file not found: infrastructure/parameters/${ENVIRONMENT}/codebuild.json"
            print_status "$RED" "    Please run: ./infrastructure/create-parameters.sh ${ENVIRONMENT}"
            return 1
        fi
        
        if deploy_stack "$CODEBUILD_STACK" "infrastructure/stacks/04-codebuild-automation.yaml" "infrastructure/parameters/${ENVIRONMENT}/codebuild.json" "CodeBuild + ECR"; then
            print_status "$GREEN" "ECR Repository URI: $ECR_REPO_URI"

            # -------------------------------------------
            # 🔨 追加: CodeBuild で初回 Docker ビルドを自動実行
            # -------------------------------------------
            print_status "$BLUE" "🏃‍♂️  Starting initial CodeBuild build (Docker image push)..."
            BUILD_ID=$(aws codebuild start-build \
                --project-name "${PROJECT_NAME}-docker-build-${ENVIRONMENT}" \
                --region "$REGION" \
                --profile "$PROFILE" \
                --query 'build.id' --output text --no-paginate) || {
                print_status "$RED" "❌ Failed to start CodeBuild build"
                return 1
            }

            print_status "$BLUE" "⌛ Waiting for CodeBuild build to complete... (id: $BUILD_ID)"
            aws codebuild batch-get-builds --ids "$BUILD_ID" --region "$REGION" --profile "$PROFILE" --no-paginate \
                | jq -r '.builds[0].buildStatus' | grep -q -E 'IN_PROGRESS|SUCCEEDED|FAILED' # ensure jq installed earlier

            # ポーリングループ（30秒間隔）
            while true; do
              STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --region "$REGION" --profile "$PROFILE" --query 'builds[0].buildStatus' --output text --no-paginate)
              if [ "$STATUS" == "IN_PROGRESS" ] || [ "$STATUS" == "QUEUED" ]; then
                sleep 30
              else
                break
              fi
            done

            if [ "$STATUS" == "SUCCEEDED" ]; then
              print_status "$GREEN" "✅ CodeBuild build succeeded; Docker image pushed"
            else
              print_status "$RED" "❌ CodeBuild build finished with status: $STATUS"
              return 1
            fi
        else
            print_status "$RED" "❌ CodeBuild deployment failed. Stopping."
            return 1
        fi
    elif [ "$started" == "false" ]; then
        print_status "$YELLOW" "⏭️ Skipping CodeBuild stack (before start point)"
    else
        print_status "$YELLOW" "⏭️ Skipping CodeBuild stack (explicitly skipped)"
    fi
    
    # Step 6: Deploy Callback Handler Stack
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "callback" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "callback"; then
        print_status "$BLUE" "🐳 Step 6: Deploying callback handler stack..."
        
        # Update (overwrite) ContainerImage in callback-handler.json every time
        if [ -f "infrastructure/parameters/${ENVIRONMENT}/callback-handler.json" ]; then
            tmp_cb=$(mktemp)
            jq --arg img "${ECR_REPO_URI}:latest" 'map(if .ParameterKey=="ContainerImage" then .ParameterValue=$img else . end)' \
              "infrastructure/parameters/${ENVIRONMENT}/callback-handler.json" > "$tmp_cb" && \
              mv "$tmp_cb" "infrastructure/parameters/${ENVIRONMENT}/callback-handler.json"
            print_status "$GREEN" "✅ Set ContainerImage to ${ECR_REPO_URI}:latest in callback-handler.json"
        else
            print_status "$RED" "❌ Parameter file not found: infrastructure/parameters/${ENVIRONMENT}/callback-handler.json"
            print_status "$RED" "    Please run: ./infrastructure/create-parameters.sh ${ENVIRONMENT}"
            return 1
        fi
        
        if ! deploy_stack "$CALLBACK_HANDLER_STACK" "infrastructure/stacks/05-callback-handler.yaml" "infrastructure/parameters/${ENVIRONMENT}/callback-handler.json" "Callback Handler (ALB, ECS)"; then
            print_status "$RED" "❌ Callback Handler deployment failed. Stopping."
            return 1
        fi
    elif [ "$started" == "false" ]; then
        print_status "$YELLOW" "⏭️ Skipping Callback Handler stack (before start point)"
    else
        print_status "$YELLOW" "⏭️ Skipping Callback Handler stack (explicitly skipped)"
    fi
    
    # Step 7: Deploy Cosigner Stack (optional)
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "cosigner" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "cosigner"; then
        print_status "$BLUE" "👤 Step 7: Deploying cosigner stack (optional)..."
        
        # Check if cosigner parameter file exists
        if [ ! -f "infrastructure/parameters/${ENVIRONMENT}/cosigner.json" ]; then
            print_status "$RED" "❌ Parameter file not found: infrastructure/parameters/${ENVIRONMENT}/cosigner.json"
            print_status "$RED" "    Please run: ./infrastructure/create-parameters.sh ${ENVIRONMENT}"
            return 1
        fi
        
        if ! deploy_stack "$COSIGNER_STACK" "infrastructure/stacks/06-cosigner.yaml" "infrastructure/parameters/${ENVIRONMENT}/cosigner.json" "Cosigner (EC2, Nitro Enclave)"; then
            print_status "$RED" "❌ Cosigner deployment failed. Stopping."
            return 1
        fi
    elif [ "$started" == "false" ]; then
        print_status "$YELLOW" "⏭️ Skipping Cosigner stack (before start point)"
    else
        print_status "$YELLOW" "⏭️ Skipping Cosigner stack (explicitly skipped)"
    fi
    
    # Final status
    if [ "$DRY_RUN" == "true" ]; then
        print_status "$GREEN" "🔍 DRY RUN completed successfully!"
        print_status "$BLUE" "📊 Would deploy the following stacks:"
    else
        print_status "$GREEN" "🎉 Deployment completed successfully!"
        print_status "$BLUE" "📊 Deployment Summary (6 stacks):"
    fi
    

    print_status "$GREEN" "  1️⃣ Foundation Stack: $FOUNDATION_STACK"
    print_status "$GREEN" "  2️⃣ Security Stack: $SECURITY_STACK"
    print_status "$GREEN" "  3️⃣ DNS Stack: $DNS_STACK"
    print_status "$GREEN" "  4️⃣ CodeBuild + ECR: $CODEBUILD_STACK"
    print_status "$GREEN" "  5️⃣ Callback Handler: $CALLBACK_HANDLER_STACK"
    print_status "$GREEN" "  6️⃣ Cosigner: $COSIGNER_STACK"
    
    print_status "$BLUE" "================================================="
    print_status "$BLUE" "📦 Container Image: $ECR_REPO_URI:latest"
    print_status "$BLUE" "🔒 SSL Certificate: callback-handler.internal"
    if [ -n "$SSL_CERT_ARN" ]; then
        print_status "$BLUE" "🔒 SSL Certificate ARN: $SSL_CERT_ARN"
    fi
    
    if [ "$DRY_RUN" != "true" ]; then
        print_status "$YELLOW" "🔗 Next steps:"
        print_status "$YELLOW" "  1. ✅ Verify ECS service is running"
        print_status "$YELLOW" "  2. 🔍 Check Application Load Balancer health"
        print_status "$YELLOW" "  3. 🔗 Configure Cosigner with pairing token (see README section 5)"
        print_status "$YELLOW" "  4. 🔗 Test callback endpoint connectivity"
        print_status "$GREEN" ""
        print_status "$GREEN" "🎉 All certificates have been automatically registered to SSM Parameter Store!"
    fi
}

# Run main function
main "$@" 