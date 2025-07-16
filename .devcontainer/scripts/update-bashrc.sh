#!/bin/bash

# .bashrcを編集するためのスクリプト
# bashrcのパス
BASHRC_PATH="/home/node/.bashrc"

# 既に追加済みかチェックするためのマーカー
MARKER="# --- CUSTOM SETTINGS ADDED BY DEVCONTAINER ---"

# PS1の設定で\wを\Wに置換（ディレクトリパスを現在のディレクトリ名のみの表示に変更）
if [ -f "$BASHRC_PATH" ]; then
  # バックアップを作成
  cp "$BASHRC_PATH" "${BASHRC_PATH}.bak"
  
  # PS1が設定されている行のみを編集（\wを\Wに置換）
  sed -i '/PS1=/s/\\w/\\W/g' "$BASHRC_PATH"
  echo "PS1設定行の\wを\Wに置換しました"
fi

# direnvの設定を追加（install-tools.shですでに設定されている可能性があるため厳密にチェック）
if [ -f "$BASHRC_PATH" ] && ! grep -q "eval \"\$(direnv hook bash)\"" "$BASHRC_PATH"; then
  echo 'eval "$(direnv hook bash)"' >> "$BASHRC_PATH"
  echo "direnvの自動起動設定を追加しました"
else
  echo "direnvの設定は既に追加されています"
fi

# .bashrcが存在し、かつマーカーが含まれていない場合のみ編集を実行
if [ -f "$BASHRC_PATH" ] && ! grep -q "$MARKER" "$BASHRC_PATH"; then
  # .bashrcの末尾に追加する内容
  cat << EOF >> "$BASHRC_PATH"

$MARKER
# AWS CLIの補完を有効化
complete -C '/usr/local/bin/aws_completer' aws

# カスタムエイリアス
alias ll='ls -la'

# ワークスペースディレクトリでdirenvを自動的に許可する
if [ -f "/workspaces/\${PWD##*/}/.envrc" ]; then
  cd "/workspaces/\${PWD##*/}" && direnv allow
fi
EOF
  echo "bashrcの編集が完了しました"
else
  echo "bashrcは既に編集済みです、またはファイルが見つかりません"
fi 