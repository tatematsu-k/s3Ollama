# 利用者向けマニュアル

本マニュアルでは、s3Ollama プラットフォームを利用してバッチ処理を実行する手順を説明します。

## 1. 入力データの準備

1. システム管理者から共有された「入力用 S3 バケット名」を確認します。
2. バケット内に任意のプレフィックス (例: `projects/sample-job`) を作成します。
3. 以下のファイル/ディレクトリ構成でアップロードします。

```
projects/sample-job/
├── contexts/
│   ├── overview.md
│   └── requirements.txt
└── prompt.txt
```

- `contexts/` ディレクトリ配下のファイルは、モデルに渡す補助コンテキストとして使用されます。サブディレクトリも利用可能です。
- `prompt.txt` はモデルに渡すメインプロンプトです。`{{context}}` プレースホルダを記述すると、contexts の内容がその位置に挿入されます。
- `prompt.txt` 以外のファイル名を利用したい場合は API 呼び出し時に `prompt_file` を指定してください。

## 2. API 呼び出し

システム管理者から共有された API エンドポイント (例: `https://xxxxx.execute-api.ap-northeast-1.amazonaws.com/submit`) を利用します。

### リクエスト例

```http
POST /submit HTTP/1.1
Host: xxxxx.execute-api.ap-northeast-1.amazonaws.com
Content-Type: application/json

{
  "s3_prefix": "projects/sample-job",
  "model": "llama2",
  "output_file": "result.md"
}
```

### パラメータ一覧

| パラメータ | 必須 | 説明 |
| ---------- | ---- | ---- |
| `s3_prefix` | 必須 | 入力バケット内のプレフィックス。`contexts/` および `prompt.txt` が格納されているディレクトリを指します。 |
| `model` | 任意 | 使用する Ollama モデル名。省略時はシステムデフォルト。 |
| `prompt_file` | 任意 | プロンプトファイル名。省略時は `prompt.txt`。 |
| `output_file` | 任意 | 出力ファイル名。省略時は `output.txt`。 |
| `vcpus` | 任意 | ジョブに割り当てる vCPU 数。数値を指定。 |
| `memory` | 任意 | ジョブに割り当てるメモリ (MiB)。 |
| `timeout_seconds` | 任意 | ジョブのタイムアウト (秒)。 |
| `job_name` | 任意 | AWS Batch ジョブ名。省略時は自動生成。 |

### レスポンス例

```json
{
  "message": "Job submitted",
  "jobId": "c1c2d3e4-5678-90ab-cdef-111213141516",
  "jobName": "ollama-1700000000-ab12cd34"
}
```

`jobId` を AWS コンソールまたは CLI で確認することで、ジョブの進行状況を追跡できます。

## 3. 出力の確認

- 出力結果は「出力用 S3 バケット」の同一プレフィックス (例: `projects/sample-job/result.md`) に保存されます。
- 出力ファイル名を省略した場合は `output.txt` が使用されます。
- 処理が成功すると SNS 通知に以下情報が含まれます。
  - ステータス (`SUCCEEDED` または `FAILED`)
  - 使用したモデル名
  - 入出力の S3 パス
  - エラー発生時のメッセージ

## 4. エラーハンドリング

### API レベルのエラー

- 400 Bad Request: リクエストボディの JSON フォーマットエラー、必須パラメータ不足。
- 500 Internal Server Error: Lambda 内部エラー。システム管理者へ連絡してください。

### バッチジョブの失敗

- SNS 通知で `status: FAILED` が送信されます。
- 出力バケットに結果ファイルは作成されません (途中結果が残る場合は削除してください)。
- 詳細は AWS Batch のログ (CloudWatch Logs) を確認します。

## 5. ベストプラクティス

- `contexts/` のファイルは用途ごとに小さく分割すると管理が容易です。
- 大きなファイルを扱う場合は Spot 中断を考慮して `timeout_seconds` を長めに設定してください。
- 冪等性を担保したい場合は `job_name` に一意なプレフィックスを付けて管理します。

## 6. よくある質問 (FAQ)

**Q. 同じプレフィックスで複数回実行するとどうなりますか？**
: 出力バケットの同名ファイルは上書きされます。必要に応じて `output_file` でバージョン管理してください。

**Q. contexts が存在しない場合は？**
: プロンプトファイルのみで実行されます。`{{context}}` プレースホルダは空文字列に置き換えられます。

**Q. モデル実行時間が長すぎる場合は？**
: `timeout_seconds` を調整するか、Batch Job Definition のデフォルトを運用チームに依頼して変更してください。

以上で利用手順は完了です。
