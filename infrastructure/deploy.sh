#!/bin/bash

# Fireblocks Callback Handler Deployment Script
# このスクリプトは、ECS Fargate上にCallback Handlerをデプロイします

set -e

# カラーコード定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ロギング関数
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# AWSプロファイルオプション生成
get_aws_profile_option() {
    if [ -n "$AWS_PROFILE" ]; then
        echo "--profile $AWS_PROFILE"
    else
        echo ""
    fi
}

# ヘルプ表示
show_help() {
    echo "使用方法: $0 [オプション]"
    echo ""
    echo "オプション:"
    echo "  -p, --profile PROFILE   AWS プロファイルを指定"
    echo "  -r, --region REGION     AWS リージョンを指定（デフォルト: ap-northeast-1）"
    echo "  --force-recreate        問答無用でスタックを削除して再作成する"
    echo "  -h, --help              このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0                              # デフォルトプロファイルを使用"
    echo "  $0 -p production                # productionプロファイルを使用"
    echo "  $0 --profile dev --region us-east-1  # devプロファイルとus-east-1リージョンを使用"
    echo "  $0 --force-recreate             # スタックを強制的に再作成"
    echo ""
}

# 設定
REGION="ap-northeast-1"
STACK_NAME="fireblocks-callback-infrastructure"
REPOSITORY_NAME="fireblocks-callback"
IMAGE_TAG="latest"
CLUSTER_NAME="fireblocks-callback-cluster"
SERVICE_NAME="callback-handler-service"
AWS_PROFILE=""
FORCE_RECREATE=false
RECREATE_STACK=false

# AWS CLI設定確認
check_aws_cli() {
    log "AWS CLI設定を確認しています..."
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLIがインストールされていません"
        exit 1
    fi
    
    PROFILE_OPTION=$(get_aws_profile_option)
    
    if ! aws sts get-caller-identity $PROFILE_OPTION &> /dev/null; then
        error "AWS認証が設定されていません"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_OPTION --query Account --output text)
    log "AWS Account ID: $ACCOUNT_ID"
    success "AWS CLI設定完了"
}

# Docker設定確認
check_docker() {
    log "Docker設定を確認しています..."
    
    if ! command -v docker &> /dev/null; then
        error "Dockerがインストールされていません"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Dockerデーモンが起動していません"
        exit 1
    fi
    
    success "Docker設定完了"
}

# 証明書ファイルの確認と設定
setup_certificates() {
    log "証明書ファイルの設定を確認しています..."
    
    local cert_dir="../app/certs"
    local callback_private_key_file="$cert_dir/callback_private.pem"
    local cosigner_public_key_file="$cert_dir/cosigner_public.pem"
    
    # 証明書ファイルの存在確認
    if [ ! -f "$callback_private_key_file" ]; then
        error "Callback private key file not found: $callback_private_key_file"
        echo "以下のファイルが必要です:"
        echo "  - $callback_private_key_file (Callback handler private key)"
        echo "  - $cosigner_public_key_file (Cosigner public key)"
        exit 1
    fi
    
    if [ ! -f "$cosigner_public_key_file" ]; then
        error "Cosigner public key file not found: $cosigner_public_key_file"
        echo "以下のファイルが必要です:"
        echo "  - $callback_private_key_file (Callback handler private key)"
        echo "  - $cosigner_public_key_file (Cosigner public key)"
        exit 1
    fi
    
    success "証明書ファイルの存在確認完了"
}

# SSM Parameter Storeに証明書を保存
upload_certificates_to_ssm() {
    log "証明書をSSM Parameter Storeに保存しています..."
    
    local cert_dir="../app/certs"
    local callback_private_key_file="$cert_dir/callback_private.pem"
    local cosigner_public_key_file="$cert_dir/cosigner_public.pem"
    
    PROFILE_OPTION=$(get_aws_profile_option)
    
    # Callback private keyをSSMに保存
    local callback_param_name="/$STACK_NAME/callback-private-key"
    log "Callback private keyを保存中: $callback_param_name"
    
    aws ssm put-parameter \
        --name "$callback_param_name" \
        --value "file://$callback_private_key_file" \
        --type "SecureString" \
        --description "Fireblocks Callback Handler Private Key for JWT signing" \
        --overwrite \
        --region $REGION \
        $PROFILE_OPTION
    
    # Cosigner public keyをSSMに保存
    local cosigner_param_name="/$STACK_NAME/cosigner-public-key"
    log "Cosigner public keyを保存中: $cosigner_param_name"
    
    aws ssm put-parameter \
        --name "$cosigner_param_name" \
        --value "file://$cosigner_public_key_file" \
        --type "SecureString" \
        --description "Fireblocks Cosigner Public Key for JWT verification" \
        --overwrite \
        --region $REGION \
        $PROFILE_OPTION
    
    success "証明書のSSM Parameter Store保存完了"
}

# ECRリポジトリ作成
create_ecr_repository() {
    log "ECRリポジトリを作成しています..."
    
    PROFILE_OPTION=$(get_aws_profile_option)
    
    if aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $REGION $PROFILE_OPTION &> /dev/null; then
        warn "ECRリポジトリ '$REPOSITORY_NAME' は既に存在します"
    else
        aws ecr create-repository \
            --repository-name $REPOSITORY_NAME \
            --region $REGION \
            --image-scanning-configuration scanOnPush=true \
            $PROFILE_OPTION
        success "ECRリポジトリ '$REPOSITORY_NAME' を作成しました"
    fi
}

# Dockerイメージビルド
build_docker_image() {
    log "Dockerイメージをビルドしています..."
    
    if [ ! -f "../app/Dockerfile" ]; then
        error "Dockerfileが見つかりません: ../app/Dockerfile"
        exit 1
    fi
    
    cd ../app
    docker build -f Dockerfile -t $REPOSITORY_NAME:$IMAGE_TAG .
    cd ../infrastructure
    
    success "Dockerイメージのビルドが完了しました"
}

# ECRにログイン
login_to_ecr() {
    log "ECRにログインしています..."
    
    PROFILE_OPTION=$(get_aws_profile_option)
    
    aws ecr get-login-password --region $REGION $PROFILE_OPTION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
    
    success "ECRログイン完了"
}

# Dockerイメージをプッシュ
push_docker_image() {
    log "DockerイメージをECRにプッシュしています..."
    
    ECR_URI=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPOSITORY_NAME:$IMAGE_TAG
    
    docker tag $REPOSITORY_NAME:$IMAGE_TAG $ECR_URI
    docker push $ECR_URI
    
    success "Dockerイメージのプッシュが完了しました"
    log "ECR URI: $ECR_URI"
}

# CloudFormationスタック状態確認
check_stack_status() {
    log "CloudFormationスタックの状態を確認しています..."
    
    PROFILE_OPTION=$(get_aws_profile_option)
    
    # 強制再作成モードの場合
    if [ "$FORCE_RECREATE" = true ]; then
        # スタックが存在するかチェック
        if aws cloudformation describe-stacks \
            --stack-name $STACK_NAME \
            --region $REGION \
            $PROFILE_OPTION &> /dev/null; then
            
            warn "強制再作成モードのため、既存スタックを削除します。"
            delete_and_recreate_stack
        else
            log "スタックが存在しません。新規作成を実行します。"
        fi
        return
    fi
    
    # スタックの存在確認
    if aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        $PROFILE_OPTION &> /dev/null; then
        
        # スタックが存在する場合、状態を取得
        STACK_STATUS=$(aws cloudformation describe-stacks \
            --stack-name $STACK_NAME \
            --region $REGION \
            --query 'Stacks[0].StackStatus' \
            --output text \
            $PROFILE_OPTION)
        
        log "現在のスタック状態: $STACK_STATUS"
        
        if [ "$STACK_STATUS" = "ROLLBACK_COMPLETE" ]; then
            warn "スタックがROLLBACK_COMPLETE状態です。更新ができません。"
            handle_rollback_complete_stack
        elif [ "$STACK_STATUS" = "CREATE_FAILED" ]; then
            warn "スタックがCREATE_FAILED状態です。"
            handle_failed_stack
        elif [ "$STACK_STATUS" = "UPDATE_ROLLBACK_COMPLETE" ]; then
            warn "スタックがUPDATE_ROLLBACK_COMPLETE状態です。"
            handle_rollback_complete_stack
        else
            log "スタック状態は正常です: $STACK_STATUS"
        fi
    else
        log "スタックが存在しません。新規作成を実行します。"
    fi
}

# ROLLBACK_COMPLETE状態の処理
handle_rollback_complete_stack() {
    echo ""
    warn "スタックが更新不可能な状態になっています。"
    echo "対処方法："
    echo "1. スタックを削除して再作成する（推奨）"
    echo "2. 手動で対処する"
    echo ""
    
    read -p "スタックを自動的に削除して再作成しますか? (y/N): " AUTO_RECOVER
    
    if [[ $AUTO_RECOVER =~ ^[Yy]$ ]]; then
        delete_and_recreate_stack
    else
        error "手動での対処が必要です。以下のコマンドでスタックを削除してください："
        echo "aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION $(get_aws_profile_option)"
        echo "その後、再度デプロイスクリプトを実行してください。"
        exit 1
    fi
}

# 失敗したスタックの処理
handle_failed_stack() {
    echo ""
    warn "スタックの作成に失敗しています。"
    echo "対処方法："
    echo "1. スタックを削除して再作成する（推奨）"
    echo "2. 手動で対処する"
    echo ""
    
    read -p "スタックを自動的に削除して再作成しますか? (y/N): " AUTO_RECOVER
    
    if [[ $AUTO_RECOVER =~ ^[Yy]$ ]]; then
        delete_and_recreate_stack
    else
        error "手動での対処が必要です。"
        exit 1
    fi
}

# スタック削除と再作成
delete_and_recreate_stack() {
    log "スタックを削除しています..."
    
    PROFILE_OPTION=$(get_aws_profile_option)
    
    # スタック削除の実行
    if aws cloudformation delete-stack \
        --stack-name $STACK_NAME \
        --region $REGION \
        $PROFILE_OPTION; then
        
        log "スタックの削除完了を待機しています..."
        echo "これには数分かかる場合があります..."
        
        # 削除完了を待機
        if aws cloudformation wait stack-delete-complete \
            --stack-name $STACK_NAME \
            --region $REGION \
            $PROFILE_OPTION; then
            
            success "スタックの削除が完了しました"
            
            # 少し待機
            log "少し待機してから再作成を開始します..."
            sleep 5
            
            # 再作成フラグを設定
            RECREATE_STACK=true
        else
            error "スタックの削除に失敗しました"
            log "スタックの削除状況を確認してください："
            echo "aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION $PROFILE_OPTION"
            exit 1
        fi
    else
        error "スタック削除コマンドの実行に失敗しました"
        exit 1
    fi
}

# 証明書ファイルの読み込み
load_ssl_certificates() {
    log "SSL証明書ファイルを読み込んでいます..."
    
    SSL_CERT_FILE="../app/certs/server-cert.pem"
    SSL_KEY_FILE="../app/certs/server-key.pem"
    
    if [ ! -f "$SSL_CERT_FILE" ]; then
        error "SSL証明書ファイルが見つかりません: $SSL_CERT_FILE"
        exit 1
    fi
    
    if [ ! -f "$SSL_KEY_FILE" ]; then
        error "SSL秘密鍵ファイルが見つかりません: $SSL_KEY_FILE"
        exit 1
    fi
    
    # 証明書ファイルの内容を読み込み
    SSL_CERT_BODY=$(cat "$SSL_CERT_FILE")
    SSL_PRIVATE_KEY=$(cat "$SSL_KEY_FILE")
    
    log "SSL証明書: $SSL_CERT_FILE"
    log "SSL秘密鍵: $SSL_KEY_FILE"
    success "SSL証明書ファイルの読み込みが完了しました"
}

# CloudFormationスタックデプロイ
deploy_infrastructure() {
    log "CloudFormationスタックをデプロイしています..."
    
    ECR_URI=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPOSITORY_NAME:$IMAGE_TAG
    PROFILE_OPTION=$(get_aws_profile_option)
    
    # 自己署名証明書を使用
    aws cloudformation deploy \
        --template-file cloudformation.yaml \
        --stack-name $STACK_NAME \
        --parameter-overrides \
            ContainerImage=$ECR_URI \
            SSLCertificateBody="$SSL_CERT_BODY" \
            SSLPrivateKey="$SSL_PRIVATE_KEY" \
        --capabilities CAPABILITY_IAM \
        --region $REGION \
        $PROFILE_OPTION
    
    success "CloudFormationスタックのデプロイが完了しました"
}

# デプロイメント状況確認
check_deployment_status() {
    log "デプロイメント状況を確認しています..."
    
    PROFILE_OPTION=$(get_aws_profile_option)
    
    # スタック状態確認
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].StackStatus' \
        --output text \
        $PROFILE_OPTION)
    
    if [ "$STACK_STATUS" != "CREATE_COMPLETE" ] && [ "$STACK_STATUS" != "UPDATE_COMPLETE" ]; then
        error "CloudFormationスタックの状態が異常です: $STACK_STATUS"
        exit 1
    fi
    
    # ECSサービス状態確認
    SERVICE_STATUS=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $REGION \
        --query 'services[0].status' \
        --output text \
        $PROFILE_OPTION)
    
    if [ "$SERVICE_STATUS" != "ACTIVE" ]; then
        error "ECSサービスの状態が異常です: $SERVICE_STATUS"
        exit 1
    fi
    
    # タスク状態確認
    RUNNING_COUNT=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $REGION \
        --query 'services[0].runningCount' \
        --output text \
        $PROFILE_OPTION)
    
    if [ "$RUNNING_COUNT" -eq 0 ]; then
        error "実行中のタスクがありません"
        exit 1
    fi
    
    success "デプロイメント状況確認完了"
}

# 出力情報表示
show_outputs() {
    log "デプロイメント情報を表示しています..."
    
    PROFILE_OPTION=$(get_aws_profile_option)
    
    # CloudFormationの出力を取得
    CALLBACK_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`CallbackURL`].OutputValue' \
        --output text \
        $PROFILE_OPTION)
    
    LOAD_BALANCER_DNS=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
        --output text \
        $PROFILE_OPTION)
    
    echo ""
    echo "==============================================="
    echo "         デプロイメント完了"
    echo "==============================================="
    echo ""
    echo "📍 Callback URL: $CALLBACK_URL"
    echo "🔗 Load Balancer DNS: $LOAD_BALANCER_DNS"
    echo "🏗️  Stack Name: $STACK_NAME"
    echo "📦 ECR Repository: $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPOSITORY_NAME"
    echo "🖥️  Region: $REGION"
    echo ""
    echo "==============================================="
    echo "         次のステップ"
    echo "==============================================="
    echo ""
    echo "1. Cosignerの設定を更新してください:"
    echo "   callbackUrl: \"$CALLBACK_URL\""
    echo ""
    echo "2. ヘルスチェックを実行してください:"
    echo "   curl -k $CALLBACK_URL/health"
    echo ""
    echo "3. ログを確認してください:"
    echo "   aws logs tail /ecs/callback-handler --follow --region $REGION"
    echo ""
    echo "4. サービス状態を確認してください:"
    echo "   aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION"
    echo ""
}

# ヘルスチェック実行
health_check() {
    log "ヘルスチェックを実行しています..."
    
    PROFILE_OPTION=$(get_aws_profile_option)
    
    CALLBACK_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`CallbackURL`].OutputValue' \
        --output text \
        $PROFILE_OPTION)
    
    # 内部からのヘルスチェック（VPC内のインスタンスから実行する必要がある）
    warn "ヘルスチェックはVPC内のインスタンスから実行する必要があります"
    echo "以下のコマンドをCosignerホストで実行してください:"
    echo "curl -k $CALLBACK_URL/health"
}

# コマンドライン引数処理
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            --force-recreate)
                FORCE_RECREATE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "不明なオプション: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # プロファイル設定の表示
    if [ -n "$AWS_PROFILE" ]; then
        log "使用するAWSプロファイル: $AWS_PROFILE"
    else
        log "使用するAWSプロファイル: デフォルト"
    fi
    log "使用するリージョン: $REGION"
    
    # 強制再作成オプションの表示
    if [ "$FORCE_RECREATE" = true ]; then
        warn "強制再作成モードが有効です。スタックは削除されて再作成されます。"
    fi
}

# メイン処理
main() {
    echo ""
    echo "==============================================="
    echo "    Fireblocks Callback Handler Deployment"
    echo "==============================================="
    echo ""
    
    check_aws_cli
    check_docker
    setup_certificates
    upload_certificates_to_ssm
    create_ecr_repository
    build_docker_image
    login_to_ecr
    push_docker_image
    
    # スタック状態確認と自動回復
    check_stack_status
    
    # SSL証明書の読み込み
    load_ssl_certificates
    
    deploy_infrastructure
    
    # デプロイメント完了まで待機
    log "デプロイメントが完了するまで待機しています..."
    sleep 30
    
    check_deployment_status
    show_outputs
    health_check
    
    # 最終メッセージ
    if [ "$RECREATE_STACK" = true ]; then
        success "スタックの再作成を含む全ての処理が完了しました！"
    else
        success "全ての処理が完了しました！"
    fi
}

# スクリプト実行
parse_arguments "$@"
main 