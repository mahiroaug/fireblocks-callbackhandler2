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
- セキュリティグループ（Cosigner, ALB, ECS, VPC Endpoints）
- IAMロール（Cosigner, ECS Task Execution, ECS Task）
- VPCエンドポイント（S3, SSM, ECR, CloudWatch Logs）

**依存関係**: Foundation Stack

### 3. DNS Stack (03-dns.yaml)
**目的**: Private Hosted Zone管理
- Private Hosted Zone（callback-handler.internal）
- DNS設定

**依存関係**: Foundation Stack

### 4. Callback Handler Stack (04-callback-handler.yaml)
**目的**: メインアプリケーションの提供
- Application Load Balancer
- ECS Cluster、Task Definition、Service
- CloudWatch Logs、Alarms
- DNS レコード

**依存関係**: Foundation Stack, Security Stack, DNS Stack

### 5. Cosigner Stack (05-cosigner.yaml)
**目的**: Fireblocks Cosignerの提供
- EC2インスタンス（Nitro Enclave有効）
- CloudWatch監視設定
- SSMパラメータ設定

**依存関係**: Foundation Stack, Security Stack

## 📁 プロジェクト構造

```
e2e-monitor-cbh/
├── infrastructure/
│   ├── stacks/                           # CloudFormationテンプレート
│   │   ├── 01-foundation.yaml           # 基盤スタック
│   │   ├── 02-security.yaml             # セキュリティスタック
│   │   ├── 03-dns.yaml                  # DNSスタック
│   │   ├── 04-callback-handler.yaml     # コールバックハンドラースタック
│   │   └── 05-cosigner.yaml             # Cosignerスタック
│   ├── parameters/                       # パラメータファイル
│   │   └── dev/                         # 環境別パラメータ
│   │       ├── foundation.json
│   │       ├── security.json
│   │       ├── dns.json
│   │       ├── callback-handler.json
│   │       └── cosigner.json
│   └── deploy-stacks.sh                 # 統合デプロイメントスクリプト
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
   - ECS: フルアクセス
   - IAM: フルアクセス
   - Route53: フルアクセス
   - VPC: フルアクセス

### 基本的なデプロイメント

#### 1. 全スタックのデプロイ
```bash
./infrastructure/deploy-stacks.sh deploy-all
```

#### 2. 環境指定でのデプロイ
```bash
./infrastructure/deploy-stacks.sh deploy-all -e prod
```

#### 3. 個別スタックのデプロイ
```bash
./infrastructure/deploy-stacks.sh deploy-foundation
./infrastructure/deploy-stacks.sh deploy-security
./infrastructure/deploy-stacks.sh deploy-dns
./infrastructure/deploy-stacks.sh deploy-callback
./infrastructure/deploy-stacks.sh deploy-cosigner
```

### スタック管理

#### スタック状態の確認
```bash
./infrastructure/deploy-stacks.sh status
```

#### パラメータファイルの生成
```bash
./infrastructure/deploy-stacks.sh create-params
```

#### 全スタックの削除
```bash
./infrastructure/deploy-stacks.sh delete-all
```

## ⚙️ 設定のカスタマイズ

### 1. パラメータファイルの編集

デプロイ前に、環境に応じてパラメータファイルを編集してください：

```bash
# パラメータファイルの生成
./infrastructure/deploy-stacks.sh create-params

# 必要に応じてパラメータを編集
vi infrastructure/parameters/dev/cosigner.json
```

### 2. 必須パラメータの設定

#### Cosignerスタック
```json
{
    "ParameterKey": "CosignerPairingToken",
    "ParameterValue": "YOUR_PAIRING_TOKEN_HERE"
},
{
    "ParameterKey": "CosignerInstallationScript",
    "ParameterValue": "https://your-installation-script-url"
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

1. **ECS監視**
   - CPU使用率
   - メモリ使用率
   - タスク数

2. **EC2監視**
   - CPU使用率
   - メモリ使用率
   - ステータスチェック

### ログ確認

```bash
# ECSログの確認
aws logs describe-log-groups --log-group-name-prefix "/aws/ecs/e2e-monitor-cbh"

# Cosignerログの確認
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/cosigner"
```

## 🛡️ セキュリティ考慮事項

### 1. 最小権限の原則
- 各IAMロールは必要最小限の権限のみ付与
- セキュリティグループは最小限の通信のみ許可

### 2. 暗号化
- SSMパラメータストアでのSecureString使用
- VPCエンドポイント経由での暗号化通信

### 3. プライベートネットワーク
- ECSとCosignerはプライベートサブネット内で実行
- 外部通信はNAT Gateway経由のみ

## 🔄 アップデート手順

### 1. アプリケーションのアップデート
```bash
# Callback Handlerのみを更新
./infrastructure/deploy-stacks.sh deploy-callback
```

### 2. インフラストラクチャのアップデート
```bash
# 特定のスタックのみを更新
./infrastructure/deploy-stacks.sh deploy-security
```

### 3. 段階的アップデート
```bash
# 依存関係を考慮した順序でアップデート
./infrastructure/deploy-stacks.sh deploy-foundation
./infrastructure/deploy-stacks.sh deploy-security
./infrastructure/deploy-stacks.sh deploy-callback
```

## 🚨 トラブルシューティング

### 1. スタック作成の失敗

#### 依存関係エラー
```bash
# 依存スタックの状態確認
./infrastructure/deploy-stacks.sh status

# 依存スタックの再作成
./infrastructure/deploy-stacks.sh deploy-foundation
```

#### パラメータエラー
```bash
# パラメータファイルの確認
cat infrastructure/parameters/dev/cosigner.json

# パラメータの修正後、再デプロイ
./infrastructure/deploy-stacks.sh deploy-cosigner
```

### 2. セキュリティグループエラー

循環参照エラーが発生した場合：
```bash
# セキュリティスタックの削除と再作成
aws cloudformation delete-stack --stack-name e2e-monitor-cbh-security-dev
./infrastructure/deploy-stacks.sh deploy-security
```

### 3. VPCエンドポイントエラー

```bash
# VPCエンドポイントの確認
aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=vpc-xxxxx

# セキュリティスタックの再作成
./infrastructure/deploy-stacks.sh deploy-security
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