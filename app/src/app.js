/**
 * ==========================================
 * Fireblocks Callback Handler Application
 * ==========================================
 * 
 * 【概要】
 * Fireblocks Workspace向けのCallback Handlerアプリケーション
 * ECS Fargate上でHTTPサーバーとして動作し、
 * Application Load BalancerでHTTPS終端を行う構成
 * 
 * 【主要機能】
 * - HTTPサーバーによるWebhook受信（ポート3000）
 * - JWT認証による双方向のセキュアな通信
 * - Cosignerからのトランザクション署名要求の処理
 * - 構造化ログによる詳細な監視
 * - パフォーマンス測定とトラッキング
 * 
 * 【通信フロー】
 * 1. CosignerからHTTPS接続要求 (ALB port 443)
 * 2. ALBでHTTPS終端、HTTPでアプリケーションへ転送
 * 3. JWTトークンによる署名要求受信
 * 4. Cosigner公開鍵による署名検証
 * 5. 業務ロジック実行（承認/拒否判定）
 * 6. Callback秘密鍵による応答署名
 * 7. JWTトークンによる応答返却
 * 
 * 【証明書管理】
 * - 証明書はSSM Parameter Storeから動的に取得
 * - cosigner_public.pem: Cosigner署名検証用公開鍵
 * - callback_private.pem: Callback応答署名用秘密鍵
 * 
 * @author Fireblocks Team
 * @version 1.0.0
 * @since 2025
 */

// ==========================================
// 必要なモジュールのインポート
// ==========================================
const express = require("express");
const fs = require("fs");
const http = require("http");  // HTTPサーバー使用

// カスタムモジュールのインポート
const { 
  generateRequestId, 
  logInfo, 
  logError, 
  logRequest, 
  logResponse, 
  logDebug 
} = require("./logger");

const { 
  verifyJWT, 
  signJWT,
  createCallbackResponse
} = require("./jwtHandler");

// ==========================================
// 証明書は jwtHandler で動的に読み込まれます
// ==========================================

// ==========================================
// Express.jsアプリケーションの設定
// ==========================================
/**
 * Express.jsアプリケーションの初期化
 * 
 * 【設定内容】
 * - JSONリクエストの解析
 * - リクエストサイズ制限
 * - セキュリティヘッダー設定
 * - ログ出力の設定
 */
const app = express();

// JSONリクエストの解析設定
app.use(express.json({
  limit: '1mb',  // リクエストサイズの制限
  verify: (req, res, buf) => {
    req.rawBody = buf;  // 生のリクエストボディを保存
  }
}));

// セキュリティヘッダーの設定
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  next();
});

// ==========================================
// ルートエンドポイント
// ==========================================
/**
 * GET /
 * ルートエンドポイント - ヘルスチェックへのリダイレクト
 */
app.get('/', (req, res) => {
  const requestId = generateRequestId();
  logRequest(req, requestId);
  
  logInfo("Root endpoint accessed - redirecting to health check", {}, requestId);
  
  logResponse(res, requestId, 302, 0);
  res.redirect('/health');
});

// ==========================================
// ヘルスチェックエンドポイント
// ==========================================
/**
 * GET /health
 * アプリケーションの健全性を確認するエンドポイント
 */
app.get('/health', (req, res) => {
  const requestId = generateRequestId();
  const startTime = Date.now();
  
  logRequest(req, requestId);
  
  // アプリケーションの健全性チェック
  const healthStatus = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    
    // メモリ使用量
    memory: process.memoryUsage(),
    
    // 提供エンドポイント一覧
    endpoints: [
      "GET /health",
      "POST /v2/tx_sign_request"
    ]
  };
  
  const responseTime = Date.now() - startTime;
  logInfo("Health check completed", {
    status: healthStatus.status,
    uptime: healthStatus.uptime,
    memory: healthStatus.memory,
    responseTime: `${responseTime}ms`
  }, requestId);
  
  logResponse(res, requestId, 200, responseTime, healthStatus);
  res.json(healthStatus);
});

// ==========================================
// 業務ロジック実行関数
// ==========================================
/**
 * 業務ロジック実行
 * トランザクション承認/拒否の判定を行う
 * 
 * @param {Object} transactionData - トランザクションデータ
 * @param {string} requestId - リクエストID
 * @returns {Object} 業務ロジック実行結果
 */
function executeBusinessLogic(transactionData, requestId) {
  logInfo("Executing business logic", {
    txId: transactionData.txId,
    operation: transactionData.operation,
    sourceType: transactionData.sourceType,
    destType: transactionData.destType,
    asset: transactionData.asset,
    amount: transactionData.amount
  }, requestId);
  
  // ===================================
  // 承認ロジック
  // ===================================
  // 現在は全てのリクエストを拒否
  // 実際の運用では、以下のような条件を追加
  // - 金額制限チェック
  // - 時間制限チェック
  // - ホワイトリスト確認
  // - 外部APIでの承認確認
  
  const businessResult = {
    action: "REJECT",  // APPROVE または REJECT
    reason: "All transactions are rejected by default policy",
    timestamp: new Date().toISOString(),
    processingTime: Date.now()
  };
  
  logInfo("Business logic completed", {
    action: businessResult.action,
    reason: businessResult.reason,
    txId: transactionData.txId
  }, requestId);
  
  return businessResult;
}

// ==========================================
// メインエンドポイント
// ==========================================
/**
 * POST /v2/tx_sign_request
 * Cosignerからのトランザクション署名要求を処理
 */
app.post('/v2/tx_sign_request', async (req, res) => {
  const requestId = generateRequestId();
  const startTime = Date.now();
  
  logRequest(req, requestId);
  
  try {
    // ==========================================
    // JWT署名検証
    // ==========================================
    const jwt = req.body;
    if (!jwt || typeof jwt !== 'string') {
      logError("Invalid JWT format", null, {
        bodyType: typeof req.body,
        bodyLength: req.body ? req.body.length : 0
      }, requestId);
      const responseTime = Date.now() - startTime;
      logResponse(res, requestId, 400, responseTime);
      return res.status(400).json({ error: "Invalid JWT format" });
    }
    
    logDebug("JWT received", { 
      jwtLength: jwt.length,
      jwtPrefix: jwt.substring(0, 50) + "..."
    }, requestId);
    
    // JWTの検証
    const decodedJWT = await verifyJWT(jwt, requestId);
    if (!decodedJWT) {
      logError("JWT verification failed", null, {
        jwtLength: jwt.length
      }, requestId);
      const responseTime = Date.now() - startTime;
      logResponse(res, requestId, 401, responseTime);
      return res.status(401).json({ error: "JWT verification failed" });
    }
    
    logInfo("JWT verification successful", {
      txId: decodedJWT.txId,
      operation: decodedJWT.operation,
      signerId: decodedJWT.signerId
    }, requestId);
    
    // ==========================================
    // 業務ロジック実行
    // ==========================================
    const txRequestId = decodedJWT.txId || decodedJWT.requestId;
    const businessResult = executeBusinessLogic(decodedJWT, requestId);
    
    // ==========================================
    // 応答JWT生成
    // ==========================================
    const responsePayload = {
      txId: txRequestId,
      action: businessResult.action,
      timestamp: new Date().toISOString(),
      requestId: requestId
    };
    
    logDebug("Generating response JWT", {
      action: businessResult.action,
      txId: txRequestId
    }, requestId);
    
    const signedRes = await signJWT(responsePayload, requestId);
    if (!signedRes) {
      logError("Failed to generate response JWT", null, {
        payload: responsePayload
      }, requestId);
      const responseTime = Date.now() - startTime;
      logResponse(res, requestId, 500, responseTime);
      return res.status(500).json({ error: "Failed to generate response JWT" });
    }
    
    // ==========================================
    // 成功応答
    // ==========================================
    const responseTime = Date.now() - startTime;
    logInfo("Transaction processing completed", {
      txId: txRequestId,
      action: businessResult.action,
      responseTime: `${responseTime}ms`
    }, requestId);
    
    logResponse(res, requestId, 200, responseTime, { 
      action: businessResult.action, 
      txRequestId 
    });
    res.send(signedRes);  // 署名済みJWTトークンを返却
    
  } catch (e) {
    // ==========================================
    // 例外処理
    // ==========================================
    const responseTime = Date.now() - startTime;
    logError("Unexpected error processing request", e, {
      responseTime: `${responseTime}ms`
    }, requestId);
    logResponse(res, requestId, 500, responseTime);
    res.sendStatus(500);  // Internal Server Error
  }
});

// ==========================================
// HTTPサーバーの起動
// ==========================================
/**
 * HTTPサーバーの作成と起動
 * 
 * 【設定】
 * - ポート: 3000（コンテナ内部）
 * - プロトコル: HTTP（ALBでHTTPS終端）
 * - ヘルスチェック: /health
 */
const server = http.createServer(app);

// サーバー起動時の詳細ログ
const serverStartTime = Date.now();

const PORT = process.env.PORT || 3000;  // デフォルトポート3000

server.listen(PORT, () => {
  const startupTime = Date.now() - serverStartTime;
  logInfo("HTTP Callback Handler server started", {
    port: PORT,                                    // 動的ポート
    startupTime: `${startupTime}ms`,               // 起動時間
    nodeVersion: process.version,                  // Node.jsバージョン
    environment: process.env.NODE_ENV || 'development',  // 環境
    platform: 'ECS Fargate',                      // プラットフォーム
    modules: ['logger', 'jwtHandler']              // ロードされたモジュール
  });
  
  logInfo("Server configuration", {
    httpsEnabled: false,                           // HTTPサーバー（ALBでHTTPS終端）
    certificateSource: 'SSM Parameter Store',     // 証明書ソース
    endpoints: [
      "GET /health",                               // ヘルスチェックエンドポイント
      "GET /",                                     // ルートエンドポイント（リダイレクト）
      "POST /v2/tx_sign_request"                   // 提供エンドポイント
    ]
  });
});

// ==========================================
// サーバーエラーハンドリング
// ==========================================
/**
 * サーバーレベルのエラーハンドリング
 * 
 * 【対応エラー】
 * - ポート使用中エラー
 * - ネットワークエラー
 */
server.on('error', (error) => {
  logError("Server error", error, {
    port: PORT,
    code: error.code,        // エラーコード
    errno: error.errno,      // システムエラー番号
    syscall: error.syscall   // システムコール
  });
  process.exit(1);
});

// ==========================================
// プロセス終了時のグレースフルシャットダウン
// ==========================================
/**
 * SIGTERMシグナルハンドラー
 * ECS Fargateタスク停止時に呼び出される
 */
process.on('SIGTERM', () => {
  logInfo("Received SIGTERM, shutting down gracefully");
  server.close(() => {
    logInfo("Server shut down completed");
    process.exit(0);
  });
});

/**
 * SIGINTシグナルハンドラー
 * 開発環境でのCtrl+C押下時に呼び出される
 */
process.on('SIGINT', () => {
  logInfo("Received SIGINT, shutting down gracefully");
  server.close(() => {
    logInfo("Server shut down completed");
    process.exit(0);
  });
});

// ==========================================
// 未処理例外のログ出力
// ==========================================
/**
 * 未処理例外のキャッチとログ出力
 * プロセス終了前にエラー詳細を記録
 */
process.on('uncaughtException', (error) => {
  logError("Uncaught Exception", error);
  process.exit(1);  // 異常終了
});

/**
 * 未処理のPromise拒否のキャッチとログ出力
 * async/awaitのエラーハンドリング漏れを検出
 */
process.on('unhandledRejection', (reason, promise) => {
  logError("Unhandled Rejection", reason, { promise: promise.toString() });
});

/**
 * ==========================================
 * End of Fireblocks Callback Handler
 * ==========================================
 * 
 * 【運用時の注意点】
 * 1. 本番環境では logger.js の LOG_LEVELS.INFO に設定
 * 2. 証明書の定期的な更新（SSM Parameter Store）
 * 3. CloudWatch Logsの監視とアラート設定
 * 4. 業務ロジックの実装とテスト
 * 5. セキュリティ監査の実施
 * 
 * 【ECS Fargate固有の考慮事項】
 * - ALBでHTTPS終端を行うため、アプリケーションはHTTP
 * - /healthエンドポイントでヘルスチェックを実行
 * - SIGTERMシグナルでグレースフルシャットダウン
 * - CloudWatch Logsにログを出力
 * - 証明書はSSM Parameter Storeから動的取得
 * 
 * 【トラブルシューティング】
 * - logger.js のログレベルを DEBUG に設定して詳細調査
 * - aws logs tail /ecs/callback-handler --follow でログ確認
 * - SSM Parameter Storeの証明書確認
 * - ALBのターゲットグループ状態確認
 * 
 * 【今後の拡張】
 * - データベース連携
 * - 外部API連携
 * - 管理画面の実装
 * - メトリクス収集
 * - アラート機能
 */ 