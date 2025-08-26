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

FROM public.ecr.aws/lambda/nodejs:22

# 作業ディレクトリ（Lambdaベースは /var/task）
WORKDIR /var/task

# package.jsonのコピー（キャッシュ効率化）
COPY src/package*.json ./

# 本番依存のみインストール
RUN npm install --omit=dev

# アプリケーションソースコードのコピー
COPY src/ ./

# 証明書はSSM Parameter Storeから動的に取得されます

# Lambda関数エントリポイント
CMD ["app.handler"]