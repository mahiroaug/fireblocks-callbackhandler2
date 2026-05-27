# Fireblocks Callback Handler - Stack Deployment Guide

## 📋 概要

このガイドでは、Fireblocks Callback Handlerのマルチスタック構成によるデプロイメント方法を説明します。システムは5つの独立したCloudFormationスタックで構成されており、それぞれが異なるライフサイクルと責任を持っています。

## 🏗️ スタック構成

### 1. Foundation Stack (01-foundation.yaml)
**目的**: ネットワーク基盤の提供
- VPC、サブネット、Internet Gateway、NAT Gateway
- ルートテーブル、サブネットアソシエーション
- 基本的なネットワーク設定

**依存関係**: なし

### 2. Security Stack (02-security.yaml)
**目的**: セキュリティ設定の一元管理
- セキュリティグループ（Cosigner, Lambda, VPC Endpoints）
- IAMロール（Cosigner, Lambda Execution）
- KMS Customer Managed Key（Fireblocks SaaS環境別のPCR8 attestation設定）
- VPCエンドポイント（S3, SSM, KMS, API Gateway, ECR, CloudWatch Logs）

**依存関係**: Foundation Stack

### 3. CodeBuild + ECR Stack (03-codebuild-automation.yaml)
**目的**: Lambdaコンテナイメージのビルド基盤
- ECRリポジトリ
- CodeBuildプロジェクト
- ソースコードアップロード用S3

**依存関係**: Foundation Stack, Security Stack

### 4. Lambda Callback Stack (04-lambda-callback.yaml)
**目的**: メインアプリケーションの提供
- API Gateway Private REST API
- Lambda関数（コンテナイメージ）
- CloudWatch Logs

**依存関係**: Foundation Stack, Security Stack, CodeBuild + ECR Stack

### 5. Cosigner Stack (05-cosigner.yaml)
**目的**: Fireblocks Cosignerの提供
- EC2インスタンス（Nitro Enclave有効、IMDSv2必須、Amazon Linux 2023）
- Cosigner persistent storage用S3 bucketとbucket policy
- CloudWatch監視設定

**依存関係**: Foundation Stack, Security Stack

## 📁 プロジェクト構造

```
e2e-monitor-cbh/
├── infrastructure/
│   ├── stacks/                           # CloudFormationテンプレート
│   │   ├── 01-foundation.yaml           # 基盤スタック
│   │   ├── 02-security.yaml             # セキュリティスタック
│   │   ├── 03-codebuild-automation.yaml # CodeBuild + ECRスタック
│   │   ├── 04-lambda-callback.yaml      # Lambda Callbackスタック
│   │   └── 05-cosigner.yaml             # Cosignerスタック
│   ├── parameters/                       # パラメータファイル
│   │   └── dev/                         # 環境別パラメータ
│   │       ├── foundation.json
│   │       ├── security.json
│   │       ├── codebuild.json
│   │       ├── lambda-callback.json
│   │       └── cosigner.json
│   └── deploy-automated.sh              # 統合デプロイメントスクリプト
├── app/                                 # アプリケーションコード
└── README.md
```

## 🚀 デプロイメント方法

### 前提条件

1. **AWS CLI設定**
   ```bash
   aws configure --profile ****
   ```

2. **必要な権限**
   - CloudFormation: フルアクセス
   - EC2: フルアクセス
   - Lambda: フルアクセス
   - API Gateway: フルアクセス
   - CodeBuild/ECR: フルアクセス
   - IAM: フルアクセス
   - VPC: フルアクセス

### 基本的なデプロイメント

#### 1. 全スタックのデプロイ
```bash
./infrastructure/deploy-automated.sh -p <aws_profile>
```

#### 2. 環境指定でのデプロイ
```bash
./infrastructure/deploy-automated.sh -p <aws_profile> -e prod
```

#### 3. 特定スタックのみのデプロイ
```bash
./infrastructure/deploy-automated.sh -p <aws_profile> --only-stacks security
./infrastructure/deploy-automated.sh -p <aws_profile> --only-stacks cosigner
```

### スタック管理

#### スタック状態の確認
```bash
./infrastructure/deploy-automated.sh -p <aws_profile> --status
```

#### パラメータファイルの生成
```bash
./infrastructure/create-parameters.sh
```

## ⚙️ 設定のカスタマイズ

### 1. パラメータファイルの編集

デプロイ前に、環境に応じてパラメータファイルを編集してください：

```bash
# パラメータファイルの生成
./infrastructure/create-parameters.sh

# 必要に応じてパラメータを編集
vi infrastructure/parameters/dev/cosigner.json
```

### 2. 必須パラメータの設定

#### Securityスタック
```json
{
    "ParameterKey": "FireblocksSaaSEnvironment",
    "ParameterValue": "global"
}
```

`FireblocksSaaSEnvironment` は `global`, `europe`, `swiss` のいずれかを指定します。この値により、KMS Key Policy の PCR8 attestation 値をFireblocks SaaS環境に合わせて切り替えます。

#### Cosignerスタック
`cosigner.json` で設定するのは EC2 起動に必要な値のみです。Pairing token とインストールパッケージURLは CloudFormation には保存せず、Fireblocks Consoleから取得して運用担当者がEC2上で `install.sh` 実行時に入力します。

```json
{
    "ParameterKey": "InstanceType",
    "ParameterValue": "c5.xlarge"
},
{
    "ParameterKey": "KeyPairName",
    "ParameterValue": "YOUR_KEY_PAIR_NAME"
}
```

#### Callback Handlerスタック
```json
{
    "ParameterKey": "SSLCertificateArn",
    "ParameterValue": "arn:aws:acm:ap-northeast-1:YOUR_ACCOUNT:certificate/YOUR_CERT_ID"
},
{
    "ParameterKey": "ContainerImage",
    "ParameterValue": "YOUR_ECR_URI:latest"
}
```

## 🔧 高度な設定

### 環境変数の設定

スクリプト内で以下の環境変数を変更できます：

```bash
export REGION="ap-northeast-1"
export PROFILE="****"
export ENVIRONMENT="dev"
```

### カスタムスタック名

```bash
export STACK_PREFIX="your-custom-prefix"
```

## 📊 監視とログ

### CloudWatch監視

各スタックには以下の監視機能が含まれています：

1. **Lambda/API Gateway監視**
   - Lambda実行ログ
   - API Gatewayアクセスログ
   - エラー率

2. **Cosigner EC2監視**
   - CPU使用率
   - ステータスチェック

### ログ確認

```bash
# Lambdaログの確認
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/e2e-monitor-cbh"

# Cosignerログの確認
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/e2e-monitor-cbh"
```

## 🛡️ セキュリティ考慮事項

### 1. 最小権限の原則
- 各IAMロールは必要最小限の権限のみ付与
- セキュリティグループは最小限の通信のみ許可

### 2. 暗号化
- SSMパラメータストアでのSecureString使用
- VPCエンドポイント経由での暗号化通信

### 3. プライベートネットワーク
- LambdaとCosignerはプライベートサブネット内で実行
- 外部通信はNAT Gateway経由のみ

## 🔄 アップデート手順

### 1. アプリケーションのアップデート
```bash
# Callback Handlerのみを更新
./infrastructure/deploy-automated.sh -p <aws_profile> --only-stacks lambda
```

### 2. インフラストラクチャのアップデート
```bash
# 特定のスタックのみを更新
./infrastructure/deploy-automated.sh -p <aws_profile> --only-stacks security
```

### 3. 段階的アップデート
```bash
# 依存関係を考慮した順序でアップデート
./infrastructure/deploy-automated.sh -p <aws_profile> --from-stack security
```

## 🚨 トラブルシューティング

### 0. EC2アクセス権がない場合の受け渡し

IaC担当はCloudFormation出力値と入力ルールを運用担当者へ渡し、EC2上の状態確認は運用担当者が実施します。

IaC担当が渡す値:
- S3 bucket name: `CosignerS3BucketName`（ARNではなくバケット名）
- CMK ARN: `CosignerKMSKeyArn`
- Callback URL: `04-lambda-callback` スタックの `CallbackUrl` 出力値（インストール時に渡す値は `.../<env>/callback` まで）
- Callback public key: `certs/callback_public.pem`
- Fireblocks SaaS環境: `global`, `europe`, `swiss`

Fireblocksは保存したCallback URLをもとに、実際の署名要求では `/callback/v2/tx_sign_request` を呼び出します。API Gateway側は `/callback/{proxy+}` でこの実リクエストを受けます。

運用担当者がEC2上で確認するコマンド:
```bash
sudo ./fireblocks/cosigner get-status
sudo ./fireblocks/cosigner logs
sudo ./fireblocks/cosigner list-users
```

Fireblocks Console側の確認:
- Pairing token はMainnetでは1時間以内に使用する
- Installation package URL は有効期限内に使用する
- API user が他のCo-signerと未ペアリングである
- Workspace Owner がMPC key share承認通知を確認できる

### 1. スタック作成の失敗

#### 依存関係エラー
```bash
# 依存スタックの状態確認
./infrastructure/deploy-automated.sh -p <aws_profile> --status

# 依存スタックの再作成
./infrastructure/deploy-automated.sh -p <aws_profile> --only-stacks foundation
```

#### パラメータエラー
```bash
# パラメータファイルの確認
cat infrastructure/parameters/dev/cosigner.json

# パラメータの修正後、再デプロイ
./infrastructure/deploy-automated.sh -p <aws_profile> --only-stacks cosigner
```

### 2. セキュリティグループエラー

循環参照エラーが発生した場合：
```bash
# セキュリティスタックの削除と再作成
aws cloudformation delete-stack --stack-name e2e-monitor-cbh-security-dev
./infrastructure/deploy-automated.sh -p <aws_profile> --only-stacks security
```

### 3. VPCエンドポイントエラー

```bash
# VPCエンドポイントの確認
aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=vpc-xxxxx

# セキュリティスタックの再作成
./infrastructure/deploy-automated.sh -p <aws_profile> --only-stacks security
```

## 📞 サポート

問題が発生した場合は、以下の情報を含めてお問い合わせください：

1. **エラーメッセージ**
2. **CloudFormationイベント**
3. **使用したコマンド**
4. **環境情報**
5. **パラメータファイル内容**

```bash
# デバッグ情報の取得
aws cloudformation describe-stack-events --stack-name YOUR_STACK_NAME
aws cloudformation describe-stack-resources --stack-name YOUR_STACK_NAME
```

---

**注意**: このマルチスタック構成により、各コンポーネントの独立したライフサイクル管理が可能になり、システムの保守性と拡張性が大幅に向上します。
