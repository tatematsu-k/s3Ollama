# 環境構築・デプロイ手順

## 前提条件

- macOS / Linux 環境を想定
- [Terraform](https://developer.hashicorp.com/terraform/downloads) 1.5 以上
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- Terraform 実行用 IAM ユーザー/ロール (AdministratorAccess 相当)
- AWS Batch から利用可能な VPC / サブネット (プライベート/パブリックどちらでも可、インターネットアクセス可能なルートが必要)
- Batch ジョブで利用するコンテナイメージを格納した ECR リポジトリ

## 1. リポジトリの取得

```bash
git clone https://github.com/your-org/s3Ollama.git
cd s3Ollama
```

## 1.1 ローカル開発環境 (任意)

Python 依存関係は `Makefile` からインストールできます。

```bash
make install
make test
```

Docker ベースの開発環境を利用する場合は、以下のコマンドでビルドとシェル起動が可能です。

```bash
make docker-build
make docker-shell
```

## 2. Terraform 変数の設定

`infrastructure/terraform` ディレクトリに移動し、`terraform.tfvars` (または同等の変数入力手段) を用意します。

```hcl
project      = "s3ollama"
environment  = "dev"
region       = "ap-northeast-1"
vpc_id       = "vpc-xxxxxxxx"
subnet_ids   = ["subnet-aaaa", "subnet-bbbb"]
batch_job_image = "xxxxxxxxxxx.dkr.ecr.ap-northeast-1.amazonaws.com/ollama-runner:latest"
default_tags = {
  Owner = "platform-team"
}
```

必要に応じて以下の変数を調整してください。

- `batch_instance_types`: Spot で利用するインスタンスタイプのリスト
- `batch_spot_bid_percentage`: オンデマンド価格に対する入札上限 (パーセント)
- `job_vcpus` / `job_memory`: ジョブごとの vCPU / メモリ割当
- `ollama_model`: デフォルトで使用する Ollama モデル
- `default_prompt_file`, `default_output_file`: ファイル名のデフォルト

## 3. Terraform の初期化とデプロイ

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

`terraform apply` が完了すると、以下が出力されます。

- 入力・出力 S3 バケット名
- SNS トピック ARN
- API Gateway エンドポイント URL

## 4. API 認証 (任意)

本構成では API Gateway に認証を設定していません。外部公開する場合は Cognito、IAM 認証、API キーなどを追加することを推奨します。

## 5. コンテナイメージの準備

Batch ジョブで使用するコンテナには以下がインストールされている必要があります。

- `ollama` バイナリ
- `python3` と `pip`
- `boto3`
- 本リポジトリ `job/` ディレクトリの中身 (イメージ内の `/opt/runner` などに配置し、エントリポイントで `python -m runner` を実行できるようにする)

例: Dockerfile の一部 (抜粋)

```dockerfile
FROM ubuntu:22.04

# Ollama のインストール (公式手順に従う)
RUN curl -fsSL https://ollama.ai/install.sh | sh

# Python 依存関係
RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*
COPY job /opt/runner
WORKDIR /opt/runner
RUN pip3 install boto3

ENTRYPOINT ["python3", "-m", "runner"]
```

## 6. 動作確認

1. 入力バケットに以下のような構成でファイルをアップロードします。

```
input-prefix/
├── contexts/
│   ├── context1.txt
│   └── design.md
└── prompt.txt
```

2. API エンドポイントに対して以下のリクエストを送信します。

```bash
curl -X POST \
  "$API_ENDPOINT/submit" \
  -H "Content-Type: application/json" \
  -d '{
    "s3_prefix": "input-prefix",
    "model": "llama2",
    "output_file": "result.md"
  }'
```

3. AWS Batch のコンソールでジョブが起動し、完了後に出力バケットへファイルが保存され SNS 通知が届くことを確認します。

## 7. 後片付け

Terraform の管理下にあるリソースを削除する際は、`terraform destroy` を実行してください。

```bash
terraform destroy
```

S3 バケットにオブジェクトが残っていると削除に失敗するため、事前に空にしてください。
