# ==========================================
# Fireblocks Callback Handler Dockerfile
# ==========================================
# 
# 【概要】
# Node.js 22を使用したCallback Handlerアプリケーション
# AWS Lambda Container Image環境での動作に最適化
# 
# 【構造】
# - src/: アプリケーションソースコード
# - 証明書: SSM Parameter Storeから動的取得
# - Lambda Handler: exports.handler
#
# @version 3.0.0 (Lambda専用)

FROM node:22-alpine

# 作業ディレクトリの設定
WORKDIR /app

# package.jsonとpackage-lock.jsonのコピー（キャッシュ効率化）
COPY src/package*.json ./

# 依存関係のインストール
RUN npm install --only=production

# 注意: aws-lambda-ric（Lambda Runtime Interface Emulator）は本番環境では不要
# AWS Lambda Container Image環境ではAWSが提供するランタイムを使用

# アプリケーションソースコードのコピー
COPY src/ ./

# 証明書はSSM Parameter Storeから動的に取得されます

# 非rootユーザーでの実行（セキュリティ向上）
RUN addgroup -g 1001 -S nodejs \
  && adduser -S nodejs -u 1001

# アプリケーションファイルの権限設定
RUN chown -R nodejs:nodejs /app

# 非rootユーザーに切り替え
USER nodejs

# Lambda関数エントリポイント
CMD ["app.handler"] 