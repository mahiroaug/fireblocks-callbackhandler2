#!/bin/bash

# Docker 設定ディレクトリを作成
mkdir -p ~/.docker

# シンプルな認証設定を作成
echo '{
  "auths": {}
}' > ~/.docker/config.json

# セキュリティのため適切なパーミッションを設定
chmod 600 ~/.docker/config.json

echo "Docker認証設定を作成しました" 