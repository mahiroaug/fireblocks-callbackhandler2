/**
 * ==========================================
 * Fireblocks Callback Handler Application
 * ==========================================
 * 
 * 【概要】
 * Fireblocks Workspace向けのCallback Handlerアプリケーション
 * AWS Lambda 上で動作し、API Gateway でHTTPS終端を行う構成
 * 
 * 【主要機能】
 * - Lambda HandlerによるWebhook受信
 * - JWT認証による双方向のセキュアな通信
 * - Cosignerからのトランザクション署名要求の処理
 * - 構造化ログによる詳細な監視
 * - パフォーマンス測定とトラッキング
 * 
 * 【通信フロー】
 * 1. Cosigner → API Gateway (HTTPS) → Lambda関数実行
 * 2. JWTトークンによる署名要求受信
 * 3. Cosigner公開鍵による署名検証
 * 4. 業務ロジック実行（承認/拒否判定）
 * 5. Callback秘密鍵による応答署名
 * 6. JWTトークンによる応答返却
 * 
 * 【証明書管理】
 * - SSM Parameter Store から動的に取得
 * - cosigner_public.pem: Cosigner署名検証用公開鍵
 * - callback_private.pem: Callback応答署名用秘密鍵
 * 
 * @author Fireblocks Team
 * @version 3.0.0 (Lambda専用)
 * @since 2025
 */

// ==========================================
// 必要なモジュールのインポート
// ==========================================
const { 
  generateRequestId, 
  logInfo, 
  logError, 
  logDebug 
} = require("./logger");

const { 
  verifyJWT, 
  signJWT
} = require("./jwtHandler");

logInfo("Fireblocks Callback Handler starting", {
  functionName: process.env.AWS_LAMBDA_FUNCTION_NAME,
  environment: process.env.NODE_ENV || 'development',
  version: '3.0.0'
});

// ==========================================
// ヘルスチェック情報生成
// ==========================================
/**
 * ヘルスチェック情報の生成
 * @param {Object} context - Lambda context
 * @returns {Object} ヘルスチェック情報
 */
function generateHealthStatus(context) {
  return {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: '3.0.0',
    environment: process.env.NODE_ENV || 'development',
    memory: process.memoryUsage(),
    lambda: {
      functionName: context.functionName,
      functionVersion: context.functionVersion,
      awsRequestId: context.awsRequestId
    },
    endpoints: ["GET /health", "POST /callback"]
  };
}

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
async function executeBusinessLogic(transactionData, requestId) {
  logInfo("Executing business logic (delayed approval mode)", {
    txId: transactionData.txId,
    operation: transactionData.operation,
    sourceType: transactionData.sourceType,
    destType: transactionData.destType,
    asset: transactionData.asset,
    amount: transactionData.amount
  }, requestId);

  const start = Date.now();
  const delayMs = Number(process.env.APPROVAL_DELAY_MS || 1000);
  await new Promise((resolve) => setTimeout(resolve, delayMs));

  const businessResult = {
    action: "APPROVE",
    reason: "Approved after delayed review",
    timestamp: new Date().toISOString(),
    processingTime: Date.now() - start
  };

  logInfo("Business logic completed", {
    action: businessResult.action,
    reason: businessResult.reason,
    txId: transactionData.txId,
    waitedMs: delayMs
  }, requestId);

  return businessResult;
}

// ==========================================
// JWT処理関数
// ==========================================
/**
 * トランザクション署名要求の処理ロジック
 * 
 * @param {string} jwtToken - JWTトークン
 * @param {string} requestId - リクエストID
 * @returns {Object} 処理結果 { success, statusCode, data, error }
 */
async function processTxSignRequest(jwtToken, requestId) {
  const startTime = Date.now();
  
  try {
    // JWT署名検証
    if (!jwtToken || typeof jwtToken !== 'string') {
      logError("Invalid JWT format", null, {
        bodyType: typeof jwtToken,
        bodyLength: jwtToken ? jwtToken.length : 0
      }, requestId);
      return {
        success: false,
        statusCode: 400,
        error: "Invalid JWT format"
      };
    }
    
    logDebug("JWT received", { 
      jwtLength: jwtToken.length,
      jwtPrefix: jwtToken.substring(0, 50) + "..."
    }, requestId);
    
    // JWTの検証
    const decodedJWT = await verifyJWT(jwtToken, requestId);
    if (!decodedJWT) {
      logError("JWT verification failed", null, {
        jwtLength: jwtToken.length
      }, requestId);
      return {
        success: false,
        statusCode: 401,
        error: "JWT verification failed"
      };
    }
    
    logInfo("JWT verification successful", {
      txId: decodedJWT.txId,
      operation: decodedJWT.operation,
      signerId: decodedJWT.signerId
    }, requestId);
    
    // 業務ロジック実行
    const txRequestId = decodedJWT.txId || decodedJWT.requestId;
    const businessResult = await executeBusinessLogic(decodedJWT, requestId);
    
    // 応答JWT生成
    const responsePayload = {
      txId: txRequestId,
      action: businessResult.action,
      timestamp: new Date().toISOString(),
      // CosignerからのrequestIdを必ずエコー（無い場合はtxId）
      requestId: decodedJWT.requestId || txRequestId
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
      return {
        success: false,
        statusCode: 500,
        error: "Failed to generate response JWT"
      };
    }
    
    // 成功応答
    const responseTime = Date.now() - startTime;
    logInfo("Transaction processing completed", {
      txId: txRequestId,
      action: businessResult.action,
      responseTime: `${responseTime}ms`
    }, requestId);
    
    return {
      success: true,
      statusCode: 200,
      data: signedRes,
      responseTime: responseTime
    };
    
  } catch (e) {
    const responseTime = Date.now() - startTime;
    logError("Unexpected error processing request", e, {
      responseTime: `${responseTime}ms`
    }, requestId);
    
    return {
      success: false,
      statusCode: 500,
      error: "Internal server error",
      responseTime: responseTime
    };
  }
}

// ==========================================
// Lambda Handler関数
// ==========================================
/**
 * AWS Lambda Handler関数
 * API Gateway からの要求を処理
 * 
 * @param {Object} event - API Gateway Event
 * @param {Object} context - Lambda Context
 * @returns {Object} API Gateway Response
 */
exports.handler = async (event, context) => {
  const requestId = generateRequestId();
  
  logInfo("Lambda handler invoked", {
    functionName: context.functionName,
    functionVersion: context.functionVersion,
    awsRequestId: context.awsRequestId,
    httpMethod: event.httpMethod,
    path: event.path,
    resource: event.resource,
    stage: event.requestContext?.stage
  }, requestId);
  
  try {
    // HTTP Method チェック
    if (event.httpMethod !== 'POST') {
      if (event.httpMethod === 'GET' && (event.path === '/health' || event.path === '/')) {
        // ヘルスチェックレスポンス
        const healthStatus = generateHealthStatus(context);
  
        logInfo("Health check completed", {
          status: 'healthy',
          awsRequestId: context.awsRequestId
        }, requestId);
        
        return {
          statusCode: 200,
          headers: {
            'Content-Type': 'application/json',
            'X-Content-Type-Options': 'nosniff',
            'X-Frame-Options': 'DENY',
            'X-XSS-Protection': '1; mode=block'
          },
          body: JSON.stringify(healthStatus)
        };
      }
      
      logError("Method not allowed", null, {
        method: event.httpMethod,
        path: event.path,
        awsRequestId: context.awsRequestId
      }, requestId);
      
      return {
        statusCode: 405,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Method Not Allowed' })
      };
    }
    
    // リクエストボディの取得
    let jwtToken;
    let rawTokenForLog;
    try {
      jwtToken = event.isBase64Encoded ? 
        Buffer.from(event.body, 'base64').toString() : 
        event.body;
      rawTokenForLog = jwtToken;
      // 入力の余分な空白や改行、両端の引用符を除去
      if (typeof jwtToken === 'string') {
        jwtToken = jwtToken.trim();
        if (jwtToken.startsWith('"') && jwtToken.endsWith('"')) {
          jwtToken = jwtToken.slice(1, -1).trim();
        }
        // フルダンプ要求がある場合はトークン全体を出力（検証目的のため）。
        const fullDump = (process.env.FULL_JWT_LOGGING || 'false').toLowerCase() === 'true';
        if (fullDump) {
          logDebug('JWT token (raw)', { token: rawTokenForLog }, requestId);
          logDebug('JWT token (normalized)', { token: jwtToken }, requestId);
        }
        // ログ強化: 先頭・末尾の数文字と長さを出力（通常時）
        logDebug('JWT normalized', {
          length: jwtToken.length,
          prefix: jwtToken.substring(0, 16) + '...',
          suffix: '...' + jwtToken.substring(Math.max(0, jwtToken.length - 16))
        }, requestId);
      }
    } catch (e) {
      logError("Failed to decode request body", e, {
        isBase64Encoded: event.isBase64Encoded,
        awsRequestId: context.awsRequestId
      }, requestId);
      
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Invalid request body' })
      };
    }
    
    // JWT処理の実行
    const result = await processTxSignRequest(jwtToken, requestId);

    // Lambda Response形式で返却
    const response = {
      statusCode: result.statusCode,
      headers: {
        'Content-Type': result.success ? 'text/plain' : 'application/json',
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
        'X-XSS-Protection': '1; mode=block'
      },
      body: result.success ? result.data : JSON.stringify({ error: result.error })
    };
    
    logInfo("Lambda response generated", {
      statusCode: response.statusCode,
      responseTime: result.responseTime || 0,
      awsRequestId: context.awsRequestId,
      success: result.success
    }, requestId);
    
    return response;
    
  } catch (e) {
    logError("Unexpected Lambda error", e, {
      awsRequestId: context.awsRequestId,
      event: JSON.stringify(event, null, 2)
    }, requestId);
    
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Internal server error' })
    };
  }
};

// ==========================================
// 例外処理
// ==========================================
process.on('uncaughtException', (error) => {
  logError("Uncaught Exception", error);
});

process.on('unhandledRejection', (reason, promise) => {
  logError("Unhandled Rejection", reason, { 
    promise: promise.toString()
  });
});

/**
 * ==========================================
 * Fireblocks Callback Handler
 * ==========================================
 * 
 * 【使用方法】
 * 1. Lambda Container Image としてデプロイ
 * 2. Handler設定: app.handler
 * 3. API Gateway Private REST API と統合
 * 4. 環境変数:
 *    - AWS_LAMBDA_FUNCTION_NAME: 自動設定
 *    - USE_SSM_PARAMETERS: "true"
 *    - NODE_ENV: "production"
 * 
 * 【運用ガイドライン】
 * - 証明書は SSM Parameter Store で管理
 * - CloudWatch Logs による監視
 * - 本番環境では logger.js を INFO レベルに設定
 * - 定期的なセキュリティ監査を実施
 * 
 * 【トラブルシューティング】
 * - aws logs tail /aws/lambda/function-name でログ確認
 * - SSM Parameter Store の証明書確認
 * - デバッグ時は logger.js を DEBUG レベルに設定
 */ 