#!/bin/bash

# エラー時に停止
set -e

echo "🚀 postStartコマンドを実行中..."

# direnvがインストールされているか確認
if ! command -v direnv &> /dev/null; then
  echo "🔄 direnvをインストールしています..."
  curl -sfL https://direnv.net/install.sh | bash
  
  # .bashrcにdirenvフックを追加（まだ存在しない場合）
  if ! grep -q "direnv hook bash" ~/.bashrc; then
    echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
  fi
fi

# プロジェクトのルートディレクトリに移動
cd /workspaces/BC_Monitoring_Tools

# .envrcが存在する場合、direnv allowを実行
if [ -f .envrc ]; then
  echo "🔑 direnv allowを実行しています..."
  direnv allow
else
  echo "⚠️ .envrcファイルが見つかりません。direnv allowはスキップします。"
fi

echo "✅ postStart処理が完了しました" 