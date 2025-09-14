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
              echo "  --from-stack      Start deployment from specific stack (foundation, security, codebuild, lambda, cosigner)"
  echo "  --skip-stacks     Skip specific stacks (comma-separated: foundation,security,codebuild,lambda,cosigner)"
            echo "  --only-stacks     Run only specified stacks (comma-separated), overrides --from/--skip"
            echo "  --dry-run         Show what would be deployed without actually deploying"
            echo "  --status          Show current status of all stacks"
            echo "  -h, --help        Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 -p dev_profile                    # Full deployment"
            echo "  $0 -p dev_profile --status           # Check stack status"
            echo "  $0 -p dev_profile --dry-run          # Preview deployment"
            echo "  $0 -p dev_profile --from-stack lambda # Start from Lambda stack"
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
CODEBUILD_STACK="${PROJECT_NAME}-03-codebuild-${ENVIRONMENT}"
LAMBDA_CALLBACK_STACK="${PROJECT_NAME}-04-lambda-callback-${ENVIRONMENT}"
COSIGNER_STACK="${PROJECT_NAME}-05-cosigner-${ENVIRONMENT}"

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
    show_stack_status "$CODEBUILD_STACK" "3️⃣ CodeBuild + ECR"
    show_stack_status "$LAMBDA_CALLBACK_STACK" "4️⃣ Lambda Callback (API Gateway + Lambda)"
    show_stack_status "$COSIGNER_STACK" "5️⃣ Cosigner (EC2, Nitro Enclave)"
    
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

# (Removed) Automatic SSM registration of JWT certificates
register_callback_private_key() {
    print_status "$BLUE" "🔑 Checking callback private key..."
    local callback_private_key="certs/callback_private.pem"
    local callback_param_name="/${PROJECT_NAME}/${ENVIRONMENT}/jwt/callback-private-key"

    if [ ! -f "$callback_private_key" ]; then
        print_status "$RED" "❌ JWT callback private key not found: $callback_private_key"
        print_status "$RED" "Please generate it first:"
        print_status "$YELLOW" "  mkdir -p certs && cd certs"
        print_status "$YELLOW" "  openssl genrsa -out callback_private.pem 2048"
        print_status "$YELLOW" "  openssl rsa -in callback_private.pem -outform PEM -pubout -out callback_public.pem"
        return 1
    fi

    if [ "$DRY_RUN" == "true" ]; then
        print_status "$BLUE" "🔍 [DRY RUN] Would register callback private key to SSM: $callback_param_name"
        return 0
    fi

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
}

# Function to setup SSH key for Cosigner
setup_ssh_key() {
    local key_name="${PROJECT_NAME}-cosigner-key-${ENVIRONMENT}"
    local private_key_path="certs/cosigner_ssh_key_${ENVIRONMENT}.pem"

    print_status "$BLUE" "🔑 Setting up SSH key for Cosigner: $key_name"

    # Check if key pair already exists in EC2
    if aws ec2 describe-key-pairs --key-names "$key_name" --region "$REGION" --profile "$PROFILE" &>/dev/null; then
        print_status "$GREEN" "✅ SSH key pair '$key_name' already exists in EC2. Using existing key."
        return 0
    fi

    print_status "$YELLOW" "⚠️ SSH key pair '$key_name' not found in EC2. Will create/import it."

    # Check for local private key, create if not found
    if [ ! -f "$private_key_path" ]; then
        print_status "$BLUE" "📦 Generating new SSH key pair locally..."
        mkdir -p certs
        # Generate key without passphrase, in PEM format
        ssh-keygen -t rsa -b 2048 -f "$private_key_path" -N "" -C "$key_name" -m PEM
        # Create the .pub file in the correct format
        ssh-keygen -y -f "$private_key_path" > "${private_key_path}.pub"
        print_status "$GREEN" "✅ New SSH key pair generated at $private_key_path"
    else
        print_status "$GREEN" "✅ Using existing local private key: $private_key_path"
    fi

    # Import the public key to EC2
    print_status "$BLUE" "📦 Importing public key to EC2 as '$key_name'..."
    aws ec2 import-key-pair \
        --key-name "$key_name" \
        --public-key-material "fileb://${private_key_path}.pub" \
        --region "$REGION" \
        --profile "$PROFILE" --no-paginate || {
        print_status "$RED" "❌ Failed to import SSH key pair to EC2."
        print_status "$RED" "    Please check your permissions and the key format."
        return 1
    }

    print_status "$GREEN" "✅ SSH key pair '$key_name' successfully imported to EC2."
    print_status "$YELLOW" "🔒 Important: The private key is stored at ${private_key_path}. Secure it and add it to .gitignore."
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
    
    print_status "$GREEN" "✅ Parameter files found in infrastructure/parameters/${ENVIRONMENT}/"
    
    # Step 1a: Register only callback private key to SSM (Cosigner public key is manual later)
    if ! register_callback_private_key; then
        print_status "$RED" "❌ Callback private key SSM registration failed."
        return 1
    fi
    
    # Initialize variables for cross-stack references
    local started=false
    local ECR_REPO_URI=""
    
    # Step 1b: Deploy Foundation Stack
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "foundation" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "foundation"; then
        print_status "$BLUE" "🏗️ Step 1b: Deploying foundation stack..."
        if ! deploy_stack "$FOUNDATION_STACK" "infrastructure/stacks/01-foundation.yaml" "infrastructure/parameters/${ENVIRONMENT}/foundation.json" "Foundation (VPC, Subnets)"; then
            print_status "$RED" "❌ Foundation deployment failed. Stopping."
            return 1
        fi
    elif [ "$started" == "false" ]; then
        print_status "$YELLOW" "⏭️ Skipping Foundation stack (before start point)"
    else
        print_status "$YELLOW" "⏭️ Skipping Foundation stack (explicitly skipped)"
    fi
    
    # Step 2: Deploy Security Stack
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "security" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "security"; then
        print_status "$BLUE" "🔐 Step 2: Deploying security stack..."
        if ! deploy_stack "$SECURITY_STACK" "infrastructure/stacks/02-security.yaml" "infrastructure/parameters/${ENVIRONMENT}/security.json" "Security (IAM, Security Groups)"; then
            print_status "$RED" "❌ Security deployment failed. Stopping."
            return 1
        fi
    elif [ "$started" == "false" ]; then
        print_status "$YELLOW" "⏭️ Skipping Security stack (before start point)"
    else
        print_status "$YELLOW" "⏭️ Skipping Security stack (explicitly skipped)"
    fi
    
    # Step 3: Deploy CodeBuild Stack (with integrated ECR)
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "codebuild" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "codebuild"; then
        print_status "$BLUE" "🔨 Step 3: Deploying CodeBuild automation (with ECR)..."
        
        # CodeBuild stack creates ECR repository internally - no URI update needed
        if [ ! -f "infrastructure/parameters/${ENVIRONMENT}/codebuild.json" ]; then
            print_status "$RED" "❌ Parameter file not found: infrastructure/parameters/${ENVIRONMENT}/codebuild.json"
            print_status "$RED" "    Please run: ./infrastructure/create-parameters.sh ${ENVIRONMENT}"
            return 1
        fi
        print_status "$GREEN" "✅ CodeBuild parameters ready (ECR repository will be created automatically)"
        
        if deploy_stack "$CODEBUILD_STACK" "infrastructure/stacks/03-codebuild-automation.yaml" "infrastructure/parameters/${ENVIRONMENT}/codebuild.json" "CodeBuild + ECR"; then
            # Get outputs from CodeBuild stack
            ECR_REPO_URI=$(get_stack_output "$CODEBUILD_STACK" "ECRRepositoryURI")
            SOURCE_BUCKET=$(get_stack_output "$CODEBUILD_STACK" "SourceCodeBucketName")
            
            if [ -z "$ECR_REPO_URI" ] || [ -z "$SOURCE_BUCKET" ]; then
                print_status "$RED" "❌ Failed to get required outputs from CodeBuild stack"
                return 1
            fi
            print_status "$GREEN" "✅ ECR Repository URI: $ECR_REPO_URI"
            print_status "$GREEN" "✅ Source Code Bucket: $SOURCE_BUCKET"
            
            # Upload local source code to S3
            print_status "$BLUE" "📦 Uploading local source code to S3..."
            if [ ! -d "app" ]; then
                print_status "$RED" "❌ app directory not found"
                return 1
            fi
            
            # Create source.zip with app directory and buildspec
            print_status "$BLUE" "Creating source.zip from app directory and buildspec..."
            if [ ! -f "buildspec.yml" ]; then
                print_status "$RED" "❌ buildspec.yml not found"
                return 1
            fi
            zip -r source.zip app/ buildspec.yml
            
            # Upload to S3
            aws s3 cp source.zip "s3://${SOURCE_BUCKET}/source.zip" \
                --region "$REGION" \
                --profile "$PROFILE" || {
                print_status "$RED" "❌ Failed to upload source code to S3"
                return 1
            }
            
            # Clean up
            rm -f source.zip
            print_status "$GREEN" "✅ Source code uploaded to S3"

            # -------------------------------------------
            # 🔨 CodeBuild で Docker イメージをビルド＆ECRプッシュ
            # -------------------------------------------
            print_status "$BLUE" "🏃‍♂️  Starting CodeBuild for Docker image build..."
            # Get CodeBuild project name from stack output
            CODEBUILD_PROJECT_NAME=$(get_stack_output "$CODEBUILD_STACK" "CodeBuildProjectName")
            if [ -z "$CODEBUILD_PROJECT_NAME" ]; then
                print_status "$RED" "❌ Failed to get CodeBuild project name from stack output"
                return 1
            fi
            
            BUILD_ID=$(aws codebuild start-build \
                --project-name "$CODEBUILD_PROJECT_NAME" \
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
              print_status "$GREEN" "✅ CodeBuild build succeeded; Docker image pushed to ECR"
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
        # --from-stack で途中から実行した場合もECR_REPO_URIを取得する
        if stack_exists "$CODEBUILD_STACK"; then
            ECR_REPO_URI=$(get_stack_output "$CODEBUILD_STACK" "ECRRepositoryURI")
            if [ -z "$ECR_REPO_URI" ]; then
                print_status "$RED" "❌ Failed to get ECR Repository URI from existing CodeBuild stack"
                return 1
            fi
            print_status "$GREEN" "✅ Fetched ECR Repository URI from existing stack: $ECR_REPO_URI"
        fi
    else
        print_status "$YELLOW" "⏭️ Skipping CodeBuild stack (explicitly skipped)"
    fi
    
    # Step 4: Deploy Lambda Callback Stack  
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "lambda" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "lambda"; then
        print_status "$BLUE" "🐳 Step 4: Deploying Lambda callback stack..."
        
        # Ensure ECR_REPO_URI is available. If empty (e.g., when skipping CodeBuild), try to fetch from existing stack
        if [ -z "$ECR_REPO_URI" ]; then
            if stack_exists "$CODEBUILD_STACK"; then
                ECR_REPO_URI=$(get_stack_output "$CODEBUILD_STACK" "ECRRepositoryURI")
                if [ -n "$ECR_REPO_URI" ]; then
                    print_status "$GREEN" "✅ Fetched ECR Repository URI from existing stack: $ECR_REPO_URI"
                else
                    print_status "$YELLOW" "⚠️ Could not fetch ECR Repository URI from existing CodeBuild stack outputs"
                fi
            fi
        fi

        # Update (overwrite) ContainerImage only if ECR_REPO_URI is non-empty (trimmed)
        ECR_REPO_URI_TRIMMED="${ECR_REPO_URI//[[:space:]]/}"
        if [ -n "$ECR_REPO_URI_TRIMMED" ]; then
            if [ -f "infrastructure/parameters/${ENVIRONMENT}/lambda-callback.json" ]; then
                tmp_cb=$(mktemp)
                jq --arg img "${ECR_REPO_URI_TRIMMED}:latest" 'map(if .ParameterKey=="ContainerImage" then .ParameterValue=$img else . end)' \
                  "infrastructure/parameters/${ENVIRONMENT}/lambda-callback.json" > "$tmp_cb" && \
                  mv "$tmp_cb" "infrastructure/parameters/${ENVIRONMENT}/lambda-callback.json"
                print_status "$GREEN" "✅ Set ContainerImage to ${ECR_REPO_URI_TRIMMED}:latest in lambda-callback.json"
            else
                print_status "$RED" "❌ Parameter file not found: infrastructure/parameters/${ENVIRONMENT}/lambda-callback.json"
                print_status "$RED" "    Please run: ./infrastructure/create-parameters.sh ${ENVIRONMENT}"
                return 1
            fi
        else
            print_status "$YELLOW" "⚠️ ECR_REPO_URI is empty. Skipping ContainerImage overwrite and using existing value in parameters file."
        fi
        
        # No forced API Gateway deployment version bump (simplified)

        if ! deploy_stack "$LAMBDA_CALLBACK_STACK" "infrastructure/stacks/04-lambda-callback.yaml" "infrastructure/parameters/${ENVIRONMENT}/lambda-callback.json" "Lambda Callback (API Gateway + Lambda)"; then
            print_status "$RED" "❌ Lambda Callback deployment failed. Stopping."
            return 1
        fi
    elif [ "$started" == "false" ]; then
        print_status "$YELLOW" "⏭️ Skipping Lambda Callback stack (before start point)"
    else
        print_status "$YELLOW" "⏭️ Skipping Lambda Callback stack (explicitly skipped)"
    fi
    
    # Step 5: Deploy Cosigner Stack (optional)
    if [ -z "$FROM_STACK" ] || [ "$FROM_STACK" == "cosigner" ]; then
        started=true
    fi
    
    if [ "$started" == "true" ] && ! should_skip_stack "cosigner"; then
        print_status "$BLUE" "👤 Step 5: Deploying cosigner stack (optional)..."
        
        # Setup SSH key before deploying Cosigner
        if ! setup_ssh_key; then
            print_status "$RED" "❌ SSH key setup failed. Stopping Cosigner deployment."
            return 1
        fi

        # Update KeyPairName parameter in cosigner.json
        local key_name="${PROJECT_NAME}-cosigner-key-${ENVIRONMENT}"
        local cosigner_params_file="infrastructure/parameters/${ENVIRONMENT}/cosigner.json"
        
        if [ -f "$cosigner_params_file" ]; then
            tmp_cosigner=$(mktemp)
            jq --arg key "$key_name" 'map(if .ParameterKey=="KeyPairName" then .ParameterValue=$key else . end)' \
              "$cosigner_params_file" > "$tmp_cosigner" && \
              mv "$tmp_cosigner" "$cosigner_params_file"
            print_status "$GREEN" "✅ Set KeyPairName to '$key_name' in $cosigner_params_file"
        else
            print_status "$RED" "❌ Parameter file not found: $cosigner_params_file"
            return 1
        fi
        
        # Check if cosigner parameter file exists
        if [ ! -f "infrastructure/parameters/${ENVIRONMENT}/cosigner.json" ]; then
            print_status "$RED" "❌ Parameter file not found: infrastructure/parameters/${ENVIRONMENT}/cosigner.json"
            print_status "$RED" "    Please run: ./infrastructure/create-parameters.sh ${ENVIRONMENT}"
            return 1
        fi
        
        if ! deploy_stack "$COSIGNER_STACK" "infrastructure/stacks/05-cosigner.yaml" "infrastructure/parameters/${ENVIRONMENT}/cosigner.json" "Cosigner (EC2, Nitro Enclave)"; then
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
        print_status "$BLUE" "📊 Deployment Summary (5 stacks):"
    fi
    

    print_status "$GREEN" "  1️⃣ Foundation Stack: $FOUNDATION_STACK"
    print_status "$GREEN" "  2️⃣ Security Stack: $SECURITY_STACK"
    print_status "$GREEN" "  3️⃣ CodeBuild + ECR: $CODEBUILD_STACK"
    print_status "$GREEN" "  4️⃣ Lambda Callback: $LAMBDA_CALLBACK_STACK"
    print_status "$GREEN" "  5️⃣ Cosigner: $COSIGNER_STACK"
    
    print_status "$BLUE" "================================================="
    print_status "$BLUE" "📦 Container Image: $ECR_REPO_URI:latest"
    
    if [ "$DRY_RUN" != "true" ]; then
        print_status "$YELLOW" "🔗 Next steps:"
        print_status "$YELLOW" "  1. ✅ Verify Lambda function is running"
        print_status "$YELLOW" "  2. 🔍 Check API Gateway Private REST API connectivity"
        print_status "$YELLOW" "  3. 🔗 Configure Cosigner with pairing token (see README section 5)"
        print_status "$YELLOW" "  4. 🔗 Test Lambda callback endpoint"
        print_status "$YELLOW" "  5. 🔑 After Cosigner setup, register Cosigner public key to SSM (manual)"
        print_status "$BLUE" ""
        print_status "$BLUE" "📥 Manual SSM registration command (run after obtaining cosigner_public.pem):"
        print_status "$BLUE" "  aws ssm put-parameter \\
    --name \"/${PROJECT_NAME}/${ENVIRONMENT}/jwt/cosigner-public-key\" \\
    --description \"JWT Cosigner Public Key\" \\
    --value \"file://certs/cosigner_public.pem\" \\
    --type \"SecureString\" \\
    --overwrite \\
    --region \"$REGION\" \\
    --profile \"$PROFILE\" \\
    --no-paginate"
    fi
}

# Run main function
main "$@" 