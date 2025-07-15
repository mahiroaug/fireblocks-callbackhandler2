#!/bin/bash

# ==========================================
# Fireblocks Callback Handler Setup Script
# ==========================================
# 
# このスクリプトは、プロジェクトの初期セットアップを自動化します
# 
# @version 1.0.0

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

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# プロジェクト名
PROJECT_NAME="fireblocks-callback-handler"

# 初期設定関数
init_project() {
    log "Fireblocks Callback Handler のセットアップを開始します..."
    
    cd "$PROJECT_ROOT"
    
    # プロジェクト情報の表示
    echo ""
    echo "==============================================="
    echo "    Fireblocks Callback Handler Setup"
    echo "==============================================="
    echo ""
    echo "📁 プロジェクト: $PROJECT_NAME"
    echo "📍 パス: $PROJECT_ROOT"
    echo ""
}

# 前提条件チェック
check_prerequisites() {
    log "前提条件をチェックしています..."
    
    # Node.jsの確認
    if ! command -v node &> /dev/null; then
        error "Node.js がインストールされていません"
        echo "Node.js 22以上をインストールしてください: https://nodejs.org/"
        exit 1
    fi
    
    NODE_VERSION=$(node --version)
    log "Node.js version: $NODE_VERSION"
    
    # npmの確認
    if ! command -v npm &> /dev/null; then
        error "npm がインストールされていません"
        exit 1
    fi
    
    NPM_VERSION=$(npm --version)
    log "npm version: $NPM_VERSION"
    
    # Dockerの確認
    if ! command -v docker &> /dev/null; then
        warn "Docker がインストールされていません"
        warn "Docker使用時は別途インストールが必要です"
    else
        if ! docker info &> /dev/null; then
            warn "Dockerデーモンが起動していません"
        else
            DOCKER_VERSION=$(docker --version)
            log "Docker version: $DOCKER_VERSION"
        fi
    fi
    
    # AWS CLIの確認
    if ! command -v aws &> /dev/null; then
        warn "AWS CLI がインストールされていません"
        warn "AWS デプロイメント使用時は別途インストールが必要です"
    else
        AWS_VERSION=$(aws --version)
        log "AWS CLI version: $AWS_VERSION"
        
        # AWS認証確認
        if ! aws sts get-caller-identity &> /dev/null; then
            warn "AWS認証が設定されていません"
        else
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            log "AWS Account ID: $ACCOUNT_ID"
        fi
    fi
    
    success "前提条件チェック完了"
}

# npm依存関係のインストール
install_dependencies() {
    log "npm依存関係をインストールしています..."
    
    cd "$PROJECT_ROOT/app/src"
    
    if [ -f "package.json" ]; then
        npm install
        success "npm依存関係のインストール完了"
    else
        error "package.json が見つかりません"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

# 証明書の確認
check_certificates() {
    log "証明書ファイルを確認しています..."
    
    CERT_DIR="$PROJECT_ROOT/app/certs"
    COSIGNER_PUBLIC="$CERT_DIR/cosigner_public.pem"
    CALLBACK_PRIVATE="$CERT_DIR/callback_private.pem"
    
    if [ ! -f "$COSIGNER_PUBLIC" ]; then
        warn "Cosigner公開鍵が見つかりません: $COSIGNER_PUBLIC"
        echo "以下のコマンドで配置してください:"
        echo "cp cosigner_public.pem $COSIGNER_PUBLIC"
    else
        success "Cosigner公開鍵が見つかりました"
    fi
    
    if [ ! -f "$CALLBACK_PRIVATE" ]; then
        warn "Callback秘密鍵が見つかりません: $CALLBACK_PRIVATE"
        echo "以下のコマンドで配置してください:"
        echo "cp callback_private.pem $CALLBACK_PRIVATE"
    else
        success "Callback秘密鍵が見つかりました"
    fi
}

# 権限設定
set_permissions() {
    log "ファイル権限を設定しています..."
    
    # スクリプトファイルの実行権限
    chmod +x "$PROJECT_ROOT/infrastructure/deploy.sh"
    chmod +x "$PROJECT_ROOT/scripts/setup.sh"
    
    # 証明書ファイルの権限（存在する場合）
    if [ -d "$PROJECT_ROOT/app/certs" ]; then
        find "$PROJECT_ROOT/app/certs" -name "*.pem" -exec chmod 600 {} \; 2>/dev/null || true
    fi
    
    success "ファイル権限設定完了"
}

# Git初期化（オプション）
init_git() {
    if [ ! -d "$PROJECT_ROOT/.git" ]; then
        read -p "Gitリポジトリを初期化しますか? (y/N): " INIT_GIT
        if [[ $INIT_GIT =~ ^[Yy]$ ]]; then
            log "Gitリポジトリを初期化しています..."
            
            cd "$PROJECT_ROOT"
            git init
            git add .
            git commit -m "Initial commit: Fireblocks Callback Handler project setup"
            
            success "Gitリポジトリの初期化完了"
        fi
    else
        log "Gitリポジトリは既に初期化されています"
    fi
}

# 環境設定の表示
show_environment_info() {
    log "環境設定情報を表示しています..."
    
    echo ""
    echo "==============================================="
    echo "         環境設定完了"
    echo "==============================================="
    echo ""
    echo "📁 プロジェクト構造:"
    echo "   ├── app/                  # アプリケーション"
    echo "   ├── infrastructure/       # AWS インフラ"
    echo "   ├── docs/                 # ドキュメント"
    echo "   └── scripts/              # ユーティリティ"
    echo ""
    echo "🚀 次のステップ:"
    echo "   1. 証明書ファイルの配置"
    echo "      cp cosigner_public.pem app/certs/"
    echo "      cp callback_private.pem app/certs/"
    echo ""
    echo "   2. デプロイメント実行"
    echo "      cd infrastructure"
    echo "      ./deploy.sh"
    echo ""
    echo "📖 詳細なドキュメント:"
    echo "   - docs/deployment-guide.md"
    echo "   - docs/aws-deployment-plan.md"
    echo ""
}

# ヘルプ表示
show_help() {
    echo "使用方法: $0 [オプション]"
    echo ""
    echo "オプション:"
    echo "  -h, --help     このヘルプを表示"
    echo "  --skip-deps    npm依存関係のインストールをスキップ"
    echo "  --skip-git     Git初期化をスキップ"
    echo ""
    echo "例:"
    echo "  $0                # 完全セットアップ"
    echo "  $0 --skip-deps    # 依存関係インストールをスキップ"
    echo ""
}

# メイン処理
main() {
    SKIP_DEPS=false
    SKIP_GIT=false
    
    # 引数解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --skip-git)
                SKIP_GIT=true
                shift
                ;;
            *)
                error "不明なオプション: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # セットアップ実行
    init_project
    check_prerequisites
    
    if [ "$SKIP_DEPS" = false ]; then
        install_dependencies
    else
        warn "npm依存関係のインストールをスキップしました"
    fi
    
    check_certificates
    set_permissions
    
    if [ "$SKIP_GIT" = false ]; then
        init_git
    else
        log "Git初期化をスキップしました"
    fi
    
    show_environment_info
    
    success "セットアップが完了しました！"
}

# スクリプト実行
main "$@" 