/**
 * ==========================================
 * JWT Handler Module
 * ==========================================
 * 
 * 【概要】
 * JWT（JSON Web Token）の処理を担当するモジュール
 * 
 * 【機能】
 * - JWTトークンのデコード
 * - JWTトークンの署名検証
 * - JWTトークンの生成・署名
 * - エラーハンドリング
 * 
 * @author Fireblocks Team
 * @version 1.0.0
 * @since 2025
 */

const jwt = require("jsonwebtoken");
const fs = require("fs");
const { logDebug, logInfo, logWarn, logError, logPerformance } = require("./logger");

// AWS SDK v3 - SSM Parameter Store
const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");

// ==========================================
// 証明書・鍵ファイルの読み込み
// ==========================================

/**
 * SSM Parameter Storeから証明書を取得する
 * @param {string} parameterName - パラメータ名
 * @param {string} description - 説明
 * @returns {Promise<Buffer>} 証明書データ
 */
async function loadCertificateFromSSM(parameterName, description) {
  try {
    const client = new SSMClient({
      region: process.env.AWS_REGION || 'ap-northeast-1'
    });
    
    const command = new GetParameterCommand({
      Name: parameterName,
      WithDecryption: true  // SecureString パラメータを復号化
    });
    
    logInfo(`Loading ${description} from SSM Parameter Store: ${parameterName}`);
    const response = await client.send(command);
    
    if (!response.Parameter || !response.Parameter.Value) {
      throw new Error(`Parameter ${parameterName} not found or empty`);
    }
    
    const value = Buffer.from(response.Parameter.Value, 'utf8');
    // 指紋を生成（PEM→DERのSHA-256）とPEMテキストSHA-256の両方を出力
    try {
      const crypto = require('crypto');
      const pemText = value.toString('utf8');
      const pemSha256 = crypto.createHash('sha256').update(pemText, 'utf8').digest('hex');
      // PEM → DER（-----BEGIN ...----- と -----END ...----- を除去しbase64デコード）
      const base64Body = pemText
        .replace(/-----BEGIN [^-]+-----/g, '')
        .replace(/-----END [^-]+-----/g, '')
        .replace(/\s+/g, '');
      const derBuf = Buffer.from(base64Body, 'base64');
      const derSha256 = crypto.createHash('sha256').update(derBuf).digest('hex');
      logDebug(`Loaded ${description} fingerprint`, {
        parameterName,
        sha256_der: derSha256,
        sha256_pem_text: pemSha256
      });
    } catch (e) {
      logWarn('Fingerprint calculation failed', { parameterName, error: e.message });
    }
    return value;
    
  } catch (error) {
    logError(`Failed to load ${description} from SSM Parameter Store`, error);
    throw error;
  }
}

/**
 * 証明書ファイルまたは環境変数またはSSM Parameter Storeから証明書を読み込む
 * @param {string} filePath - ファイルパス
 * @param {string} envVar - 環境変数名
 * @param {string} parameterName - SSM Parameter名
 * @param {string} description - 説明
 * @returns {Promise<Buffer>} 証明書データ
 */
async function loadCertificate(filePath, envVar, parameterName, description) {
  // 1. SSM Parameter Storeから取得を試行
  if (process.env.USE_SSM_PARAMETERS === 'true' && parameterName) {
    try {
      return await loadCertificateFromSSM(parameterName, description);
    } catch (error) {
      logError(`Failed to load ${description} from SSM Parameter Store, falling back to other methods`, error);
    }
  }
  
  // 2. 環境変数が設定されている場合は環境変数を使用
  if (process.env[envVar]) {
    logInfo(`Loading ${description} from environment variable: ${envVar}`);
    return Buffer.from(process.env[envVar], 'utf8');
  }
  
  // 3. ファイルが存在する場合はファイルを使用
  const certsDir = process.env.CERTS_DIR || 'certs';
  const relativePath = `${certsDir}/${filePath}`;
  
  try {
    if (fs.existsSync(relativePath)) {
      logInfo(`Loading ${description} from file: ${relativePath}`);
      return fs.readFileSync(relativePath);
    }
    
    throw new Error(`Certificate not found: ${description}`);
    
  } catch (error) {
    logError(`Failed to load ${description}`, error);
    throw error;
  }
}

/**
 * 証明書の初期化（非同期処理）
 * @returns {Promise<{callbackPrivateKey: Buffer, cosignerPublicKey: Buffer}>}
 */
async function initializeCertificates() {
  try {
    const callbackPrivateKey = await loadCertificate(
      "callback_private.pem", 
      "CALLBACK_PRIVATE_KEY", 
      process.env.CALLBACK_PRIVATE_KEY_PARAMETER,
      "Callback private key"
    );

    const cosignerPublicKey = await loadCertificate(
      "cosigner_public.pem", 
      "COSIGNER_PUBLIC_KEY", 
      process.env.COSIGNER_PUBLIC_KEY_PARAMETER,
      "Cosigner public key"
    );

    logInfo("Certificate initialization completed");
    return { callbackPrivateKey, cosignerPublicKey };
    
  } catch (error) {
    logError("Certificate initialization failed", error);
    throw error;
  }
}

// 証明書の初期化（起動時に実行）
let certificatesPromise = initializeCertificates();

// 証明書を取得する関数
async function getCertificates() {
  return await certificatesPromise;
}

/**
 * JWTトークンをデコードする
 * 署名検証は行わず、ペイロードのみを取得
 * 
 * @param {string} token - JWTトークン文字列
 * @param {string} requestId - リクエストID
 * @returns {Object|null} デコードされたペイロード、失敗時はnull
 */
function decodeJWT(token, requestId) {
  const startTime = Date.now();
  
  try {
    const decoded = jwt.decode(token);
    logPerformance("JWT decode", startTime, requestId);
    
    logDebug("JWT decode result", {
      decodedType: typeof decoded,
      decodedPayload: decoded,
      tokenLength: token.length
    }, requestId);
    
    return decoded;
  } catch (error) {
    logPerformance("JWT decode", startTime, requestId, { success: false });
    logError("JWT decode failed", error, { tokenLength: token.length }, requestId);
    return null;
  }
}

// 署名部分が全て0x00かを判定（base64url署名 → バイト列）
function isZeroSignature(token) {
  try {
    if (!token || typeof token !== 'string') return false;
    const parts = token.split('.');
    if (parts.length !== 3) return false;
    let sig = parts[2];
    // base64url → base64 変換 + パディング
    sig = sig.replace(/-/g, '+').replace(/_/g, '/');
    const pad = (4 - (sig.length % 4)) % 4;
    sig = sig + '='.repeat(pad);
    const buf = Buffer.from(sig, 'base64');
    if (buf.length === 0) return false;
    for (let i = 0; i < buf.length; i++) {
      if (buf[i] !== 0x00) return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

function summarizeJwt(token) {
  try {
    const parts = token.split('.');
    const [h, p, s] = parts;
    return {
      headerLength: h?.length || 0,
      payloadLength: p?.length || 0,
      signatureLength: s?.length || 0,
      headerPreview: (h || '').substring(0, 12) + '...',
      signaturePreview: '...' + (s || '').substring(Math.max(0, (s || '').length - 12))
    };
  } catch (_) {
    return {};
  }
}

function base64UrlToUtf8(b64url) {
  try {
    const b64 = b64url.replace(/-/g, '+').replace(/_/g, '/');
    const pad = (4 - (b64.length % 4)) % 4;
    const fixed = b64 + '='.repeat(pad);
    return Buffer.from(fixed, 'base64').toString('utf8');
  } catch (_) {
    return '';
  }
}

function logFullJwt(token, requestId) {
  try {
    const parts = token.split('.');
    const [h, p, s] = parts;
    const headerJson = base64UrlToUtf8(h);
    const payloadJson = base64UrlToUtf8(p);
    // 署名はそのまま(base64url)でログ
    logDebug('JWT full dump', {
      header: headerJson,
      payload: payloadJson,
      signature_b64url: s,
    }, requestId);
  } catch (e) {
    logError('Failed to log full JWT', e, {}, requestId);
  }
}

/**
 * JWTトークンの署名を検証する
 * Cosigner公開鍵を使用してトークンの署名を検証
 * 
 * @param {string} token - JWTトークン文字列
 * @param {string} requestId - リクエストID
 * @returns {Promise<Object|null>} 検証済みペイロード、失敗時はnull
 */
async function verifyJWT(token, requestId) {
  const startTime = Date.now();
  
  try {
    // 事前サマリログ（機微は出さない）
    logDebug('JWT parts summary', summarizeJwt(token), requestId);

    // フルダンプ（任意）
    const fullDump = (process.env.FULL_JWT_LOGGING || 'false').toLowerCase() === 'true';
    if (fullDump) {
      logFullJwt(token, requestId);
    }

    // ゼロ署名バイパス（環境変数でON/OFF）
    const allowZeroSig = (process.env.ALLOW_ZERO_SIGNATURE || 'false').toLowerCase() === 'true';
    if (allowZeroSig && isZeroSignature(token)) {
      logWarn('Zero signature detected; skipping verification as configured', { bypass: true }, requestId);
      const decodedNoVerify = jwt.decode(token);
      logPerformance("JWT verify (bypass)", startTime, requestId);
      return decodedNoVerify;
    }
    // ゼロ署名判定結果をログ（バイパス無効時の参考）
    logDebug('Zero signature check', {
      allowZeroSignature: allowZeroSig,
      isZero: isZeroSignature(token)
    }, requestId);

    // ヘッダーの要点をログ
    try {
      const header = jwt.decode(token, { complete: true })?.header || null;
      logDebug('JWT header', { alg: header?.alg, kid: header?.kid }, requestId);
    } catch (_) {}

    const { cosignerPublicKey } = await getCertificates();
    
    const decoded = jwt.verify(token, cosignerPublicKey, {
      algorithms: ['RS256'],
      ignoreExpiration: false
    });
    
    logPerformance("JWT verify", startTime, requestId);
    
    logDebug("JWT verify result", {
      decodedType: typeof decoded,
      decodedPayload: decoded,
      tokenLength: token.length
    }, requestId);
    
    return decoded;
  } catch (error) {
    logPerformance("JWT verify", startTime, requestId, { success: false });
    logError("JWT verify failed", error, { tokenLength: token.length }, requestId);
    return null;
  }
}

/**
 * JWTトークンに署名する
 * Callback秘密鍵を使用してペイロードに署名
 * 
 * @param {Object} payload - JWTペイロード
 * @param {string} requestId - リクエストID
 * @returns {Promise<string|null>} 署名済みJWTトークン、失敗時はnull
 */
async function signJWT(payload, requestId) {
  const startTime = Date.now();
  
  try {
    const { callbackPrivateKey } = await getCertificates();
    
    const token = jwt.sign(payload, callbackPrivateKey, {
      algorithm: 'RS256',
      expiresIn: '1h'
    });
    
    logPerformance("JWT sign", startTime, requestId);
    
    logDebug("JWT sign result", {
      payloadType: typeof payload,
      tokenLength: token.length
    }, requestId);
    
    return token;
  } catch (error) {
    logPerformance("JWT sign", startTime, requestId, { success: false });
    logError("JWT sign failed", error, { payload }, requestId);
    return null;
  }
}

/**
 * JWTトークンの詳細情報を取得する
 * デコードと署名検証を行い、包括的な情報を返す
 * 
 * @param {string} token - JWTトークン文字列
 * @param {string} requestId - リクエストID
 * @returns {Promise<Object>} JWT詳細情報オブジェクト
 */
async function getJWTDetails(token, requestId) {
  const startTime = Date.now();
  
  try {
    // デコード処理
    const decoded = decodeJWT(token, requestId);
    
    // 署名検証
    const verified = await verifyJWT(token, requestId);
    
    logPerformance("JWT details", startTime, requestId);
    
    return {
      decoded,
      verified,
      isValid: verified !== null,
      header: jwt.decode(token, { complete: true })?.header || null
    };
    
  } catch (error) {
    logPerformance("JWT details", startTime, requestId, { success: false });
    logError("JWT details failed", error, { tokenLength: token.length }, requestId);
    return {
      decoded: null,
      verified: null,
      isValid: false,
      header: null
    };
  }
}

/**
 * JWTトークンの基本的な形式チェック
 * 
 * @param {string} token - JWTトークン文字列
 * @returns {boolean} 形式が正しい場合true
 */
function isValidJWTFormat(token) {
  if (!token || typeof token !== 'string') {
    return false;
  }
  
  // JWTは3つの部分（ヘッダー.ペイロード.署名）がドットで区切られている
  const parts = token.split('.');
  return parts.length === 3;
}

/**
 * Callback用の応答ペイロードを作成
 * 
 * @param {string} action - 承認/拒否のアクション（"APPROVE" | "REJECT"）
 * @param {string} requestId - 元のリクエストID
 * @param {string} rejectionReason - 拒否理由（REJECTの場合）
 * @returns {Object} 応答ペイロード
 */
function createCallbackResponse(action, requestId, rejectionReason = null) {
  const payload = {
    action: action,
    requestId: requestId,
    timestamp: new Date().toISOString(),
    issuer: "e2e-monitor-cbh"
  };
  
  // REJECTの場合のみ拒否理由を追加
  if (action === "REJECT" && rejectionReason) {
    payload.rejectionReason = rejectionReason;
  }
  
  return payload;
}

// ==========================================
// エクスポート
// ==========================================
module.exports = {
  decodeJWT,
  verifyJWT,
  signJWT,
  getJWTDetails,
  isValidJWTFormat,
  createCallbackResponse
}; 