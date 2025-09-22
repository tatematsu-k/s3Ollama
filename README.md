# s3Ollama Platform

`s3Ollama` は、S3 に配置された入力ファイルをトリガーとして AWS Batch 上で Ollama ワークロードを実行し、処理結果を別の S3 バケットに保存した上で SNS に通知するバッチ基盤です。本リポジトリには Terraform によるインフラ構築コードと、API/Lambda、Batch ジョブ実行用スクリプト、各種ドキュメントを格納しています。

## リポジトリ構成

| パス | 説明 |
| ---- | ---- |
| `infrastructure/terraform/` | AWS リソースを構築する Terraform コード |
| `lambda/api/` | Batch ジョブを起動する API (Lambda) の実装 |
| `job/` | AWS Batch ジョブコンテナで実行するランナー実装 |
| `docs/` | 企画書、環境構築手順、利用者向けマニュアルなどのドキュメント |
| `Dockerfile` / `Makefile` | ローカル・CI 用の開発環境およびコマンド群 |

## 主要コンポーネント

- **入力 S3 バケット**: `contexts/` 配下と `prompt.txt` などのプロンプトファイルを格納します。
- **API Gateway + Lambda**: API 経由で Batch ジョブを起動し、必要なパラメータを引き渡します。
- **AWS Batch (Spot)**: Ollama コンテナをスポットインスタンス上で実行します。
- **出力 S3 バケット**: バッチ処理の結果ファイルを格納します。
- **SNS**: バッチジョブの成功/失敗を通知します。

## ドキュメント

- [環境構築・デプロイ手順](docs/environment_setup.md)
- [利用者向けマニュアル](docs/user_guide.md)
- [企画書](docs/proposal.md)
- [インフラ構成 (Mermaid 図)](docs/architecture.md)
- [TODO リスト](docs/todo.md)

## 開発メモ

- Terraform の実行には `terraform >= 1.5`、AWS Provider `~> 5.0` が必要です。
- Batch ジョブ用コンテナイメージには `ollama` CLI と `python3`、`boto3` がインストールされている必要があります。
- Terraform 実行前に `terraform.tfvars` または環境変数で VPC/Subnet などの値を設定してください。

## 開発環境の立ち上げ

### ローカル実行

```bash
make install
make lint
make test
```

### Docker コンテナ

```bash
make docker-build
make docker-shell
```

コンテナ内では `/workspace` にソースコードがマウントされており、`make test` などのコマンドをそのまま実行できます。

## CI / テスト

GitHub Actions (`.github/workflows/ci.yml`) を用意しており、Python テストと Terraform フォーマット検証が自動実行されます。

詳細は各ドキュメントを参照してください。
