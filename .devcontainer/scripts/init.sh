#!/bin/bash

# スクリプトの場所を取得
SCRIPT_DIR="$(dirname "$0")"

# 各セットアップスクリプトを実行
echo "🚀 Devcontainer初期化を開始します..."

echo "🐳 Docker設定を作成中..."
bash "$SCRIPT_DIR/setup-docker.sh"

echo "🔧 AWS CLIをインストール中..."
bash "$SCRIPT_DIR/install-aws-cli.sh"

echo "🔧 各種ツールをインストール中..."
bash "$SCRIPT_DIR/install-tools.sh"

echo "📝 bash設定を更新中..."
bash "$SCRIPT_DIR/update-bashrc.sh"

echo "✅ Devcontainer初期化が完了しました！" 