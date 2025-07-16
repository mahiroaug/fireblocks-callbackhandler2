#!/bin/bash

echo "📡 各種ツールをインストール中..."

# sudoなしでinstallできるか確認
if [ "$(id -u)" != "0" ]; then
    # 非rootユーザーの場合はsudoを使用
    sudo apt-get update && sudo apt-get install -y \
        git \
        dnsutils \
        libx11-xcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxi6 \
        libxtst6 \
        libnss3 \
        libcups2 \
        libxss1 \
        libxrandr2 \
        libasound2 \
        libpangocairo-1.0-0 \
        libatk1.0-0 \
        libgtk-3-0 \
        libxcb1 \
        fonts-noto-cjk

    # Google Chromeのリポジトリを追加（最新の方法）
    # 鍵をダウンロードして dearmor
    wget -q -O /tmp/google_signing_key.pub https://dl-ssl.google.com/linux/linux_signing_key.pub
    sudo gpg --dearmor \
        --output /usr/share/keyrings/google-linux-signing-keyring.gpg \
        /tmp/google_signing_key.pub

    # リポジトリ定義を作成
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux-signing-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
        | sudo tee /etc/apt/sources.list.d/google.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y google-chrome-stable
else
    # rootユーザーの場合
    apt-get update && apt-get install -y \
        git \
        dnsutils \
        libx11-xcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxi6 \
        libxtst6 \
        libnss3 \
        libcups2 \
        libxss1 \
        libxrandr2 \
        libasound2 \
        libpangocairo-1.0-0 \
        libatk1.0-0 \
        libgtk-3-0 \
        libxcb1 \
        fonts-noto-cjk

    # Google Chromeのリポジトリを追加（最新の方法）
    # 鍵をダウンロードして dearmor
    wget -q -O /tmp/google_signing_key.pub https://dl-ssl.google.com/linux/linux_signing_key.pub
    gpg --dearmor \
        --output /usr/share/keyrings/google-linux-signing-keyring.gpg \
        /tmp/google_signing_key.pub

    # リポジトリ定義を作成
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux-signing-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google.list
    
    apt-get update
    apt-get install -y google-chrome-stable

fi

echo "✅ 各種ツールのインストールが完了しました。" 