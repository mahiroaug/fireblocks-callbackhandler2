/**
 * ==========================================
 * Logger Module
 * ==========================================
 * 
 * 【概要】
 * 構造化ログシステムの実装
 * 
 * 【機能】
 * - JSON形式でのログ出力
 * - リクエストIDによるトラッキング
 * - パフォーマンス測定
 * - 多段階ログレベル
 * - 日本時間とUTC時間の併記
 * 
 * @author Fireblocks Team
 * @version 1.0.0
 * @since 2025
 */

const jwt = require("jsonwebtoken");

/**
 * ログレベル定義
 * 数値が小さいほど詳細なログ情報を出力
 */
const LOG_LEVELS = {
  DEBUG: 0,   // 詳細なデバッグ情報（開発時のみ）
  INFO: 1,    // 通常の情報（本番環境推奨）
  WARN: 2,    // 警告情報
  ERROR: 3    // エラー情報
};

/**
 * 現在のログレベル設定
 * 本番環境では INFO に設定することを推奨
 */
function resolveLogLevel() {
  const levelFromEnv = (process.env.LOG_LEVEL || '').toUpperCase();
  if (levelFromEnv && LOG_LEVELS[levelFromEnv] !== undefined) {
    return LOG_LEVELS[levelFromEnv];
  }
  // NODE_ENV によるデフォルト（production は INFO、それ以外は DEBUG）
  const isProd = (process.env.NODE_ENV || '').toLowerCase() === 'prod' || (process.env.NODE_ENV || '').toLowerCase() === 'production';
  return isProd ? LOG_LEVELS.INFO : LOG_LEVELS.DEBUG;
}

const CURRENT_LOG_LEVEL = resolveLogLevel();

/**
 * ISO形式のタイムスタンプを生成
 * @returns {string} UTC時間のISO形式文字列
 */
function getTimestamp() {
  const now = new Date();
  return now.toISOString(); // ISO形式でUTCタイムスタンプ
}

/**
 * 一意なリクエストIDを生成
 * リクエストの追跡に使用
 * @returns {string} ランダムな9文字の英数字文字列
 */
function generateRequestId() {
  return Math.random().toString(36).substr(2, 9);
}

/**
 * 構造化ログエントリを作成
 * 
 * @param {string} level - ログレベル（DEBUG, INFO, WARN, ERROR）
 * @param {string} message - ログメッセージ
 * @param {Object} data - 追加データオブジェクト
 * @param {string|null} requestId - リクエストID（追跡用）
 * @returns {Object} JSON形式のログエントリ
 */
function createLogEntry(level, message, data = {}, requestId = null) {
  const logEntry = {
    timestamp: getTimestamp(),    // UTC時間のISO形式
    level: level,                 // ログレベル
    message: message,             // メッセージ
    requestId: requestId,         // リクエストID
    ...data                       // 追加データ
  };
  
  // 日本時間での見やすい表示も追加
  const jstTime = new Date().toLocaleString('ja-JP', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  });
  logEntry.jstTime = jstTime;    // JST時間を併記
  
  return logEntry;
}

/**
 * デバッグレベルのログ出力
 * 開発時の詳細な情報を出力（本番では無効化推奨）
 * 
 * @param {string} message - ログメッセージ
 * @param {Object} data - 追加データ
 * @param {string|null} requestId - リクエストID
 */
function logDebug(message, data = {}, requestId = null) {
  if (CURRENT_LOG_LEVEL <= LOG_LEVELS.DEBUG) {
    const logEntry = createLogEntry('DEBUG', message, data, requestId);
    console.log(JSON.stringify(logEntry, null, 2));
  }
}

/**
 * 情報レベルのログ出力
 * 通常の動作情報を出力（本番環境推奨）
 * 
 * @param {string} message - ログメッセージ
 * @param {Object} data - 追加データ
 * @param {string|null} requestId - リクエストID
 */
function logInfo(message, data = {}, requestId = null) {
  if (CURRENT_LOG_LEVEL <= LOG_LEVELS.INFO) {
    const logEntry = createLogEntry('INFO', message, data, requestId);
    console.log(JSON.stringify(logEntry, null, 2));
  }
}

/**
 * 警告レベルのログ出力
 * 問題の兆候や注意すべき状況を出力
 * 
 * @param {string} message - ログメッセージ
 * @param {Object} data - 追加データ
 * @param {string|null} requestId - リクエストID
 */
function logWarn(message, data = {}, requestId = null) {
  if (CURRENT_LOG_LEVEL <= LOG_LEVELS.WARN) {
    const logEntry = createLogEntry('WARN', message, data, requestId);
    console.warn(JSON.stringify(logEntry, null, 2));
  }
}

/**
 * エラーレベルのログ出力
 * エラー情報とスタックトレースを出力
 * 
 * @param {string} message - ログメッセージ
 * @param {Error|null} error - エラーオブジェクト
 * @param {Object} data - 追加データ
 * @param {string|null} requestId - リクエストID
 */
function logError(message, error = null, data = {}, requestId = null) {
  if (CURRENT_LOG_LEVEL <= LOG_LEVELS.ERROR) {
    const errorData = {
      ...data,
      error: error ? {
        message: error.message,  // エラーメッセージ
        stack: error.stack,      // スタックトレース
        name: error.name         // エラータイプ
      } : null
    };
    const logEntry = createLogEntry('ERROR', message, errorData, requestId);
    console.error(JSON.stringify(logEntry, null, 2));
  }
}

/**
 * HTTPリクエストの詳細ログ出力
 * 受信したリクエストの詳細情報を記録
 * 
 * @param {Object} req - Expressリクエストオブジェクト
 * @param {string} requestId - リクエストID
 */
function logRequest(req, requestId) {
  logInfo('Incoming request', {
    method: req.method,                            // HTTPメソッド
    url: req.url,                                  // リクエストURL
    headers: req.headers,                          // リクエストヘッダー
    userAgent: req.get('User-Agent'),              // ユーザーエージェント
    contentLength: req.get('Content-Length'),      // コンテンツ長
    contentType: req.get('Content-Type'),          // コンテンツタイプ
    remoteAddress: req.connection.remoteAddress    // クライアントIPアドレス
  }, requestId);
}

/**
 * HTTPレスポンスの詳細ログ出力
 * 送信したレスポンスの詳細情報を記録
 * 
 * @param {Object} res - Expressレスポンスオブジェクト
 * @param {string} requestId - リクエストID
 * @param {number} statusCode - HTTPステータスコード
 * @param {number} responseTime - レスポンス時間（ミリ秒）
 * @param {Object|null} responseData - レスポンスデータ
 */
function logResponse(res, requestId, statusCode, responseTime, responseData = null) {
  logInfo('Outgoing response', {
    statusCode: statusCode,                    // HTTPステータスコード
    responseTime: `${responseTime}ms`,         // レスポンス時間
    responseData: responseData                 // レスポンスデータ
  }, requestId);
}

/**
 * JWTトークンの詳細ログ出力
 * JWTトークンのヘッダーとペイロードを解析してログに記録
 * 
 * @param {string} token - JWTトークン文字列
 * @param {string} requestId - リクエストID
 */
function logJWTDetails(token, requestId) {
  try {
    const header = jwt.decode(token, { complete: true })?.header;   // JWTヘッダー
    const payload = jwt.decode(token);                              // JWTペイロード
    
    logDebug('JWT Token Details', {
      header: header,                // JWTヘッダー情報
      payload: payload,              // JWTペイロード情報
      tokenLength: token.length      // トークン長
    }, requestId);
  } catch (error) {
    logError('Failed to decode JWT for logging', error, { tokenLength: token.length }, requestId);
  }
}

/**
 * パフォーマンス測定ログ出力
 * 各処理の実行時間を測定・記録
 * 
 * @param {string} operation - 処理名
 * @param {number} startTime - 開始時間（Date.now()）
 * @param {string} requestId - リクエストID
 * @param {Object} additionalData - 追加データ
 */
function logPerformance(operation, startTime, requestId, additionalData = {}) {
  const duration = Date.now() - startTime;
  logInfo(`Performance: ${operation}`, {
    duration: `${duration}ms`,    // 実行時間
    ...additionalData             // 追加データ
  }, requestId);
}

// ==========================================
// エクスポート
// ==========================================
module.exports = {
  LOG_LEVELS,
  generateRequestId,
  logDebug,
  logInfo,
  logWarn,
  logError,
  logRequest,
  logResponse,
  logJWTDetails,
  logPerformance
}; 