# ==========================================
# Fireblocks Callback Handler Dockerfile
# ==========================================
# 
# 【概要】
# Node.js 22を使用したCallback Handlerアプリケーション
# ECS Fargate環境での動作に最適化
# 
# 【構造】
# - src/: アプリケーションソースコード
# - 証明書: SSM Parameter Storeから動的取得
# - logs/: ログファイル（stdout/stderrに出力）
#
# @version 1.0.0

FROM node:22-alpine

# 作業ディレクトリの設定
WORKDIR /app

# package.jsonとpackage-lock.jsonのコピー（キャッシュ効率化）
COPY src/package*.json ./

# 依存関係のインストール
RUN npm install --only=production

# アプリケーションソースコードのコピー
COPY src/ ./

# 証明書はSSM Parameter Storeから動的に取得されます

# ログディレクトリの作成（不要だが既存の構造を維持）
RUN mkdir -p logs

# ポート3000を公開（ECS Fargate用）
EXPOSE 3000

# ヘルスチェック追加（curlをインストール）
RUN apk add --no-cache curl

# ヘルスチェック設定（HTTPサーバー用）
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# 非rootユーザーでの実行（セキュリティ向上）
RUN addgroup -g 1001 -S nodejs \
  && adduser -S nodejs -u 1001

# アプリケーションファイルの権限設定
RUN chown -R nodejs:nodejs /app

# 非rootユーザーに切り替え
USER nodejs

# アプリケーション起動
CMD ["node", "app.js"] 