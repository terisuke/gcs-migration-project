# GCS移行プロジェクト実行手順書

## 概要
このプロジェクトは、`yolov8environment`プロジェクト（cor-jp.com管理）のすべてのGCSバケットを、`u-dake`プロジェクト（u-dake.com管理）にアーカイブとして移行するものです。

異なるGoogleアカウントで管理されているため、3つのフェーズに分けて実行します。

## 前提条件
- `gcloud` コマンドがインストール済み
- 両方のアカウントでの管理者権限
  - `company@cor-jp.com` (yolov8environment)
  - `company@u-dake.com` (u-dake)
- 十分なローカルディスク容量（データ量の2倍以上推奨）

## 実行手順

### 📥 フェーズ1: ダウンロード

**実行アカウント**: `company@cor-jp.com`

1. cor-jp.comアカウントでログイン:
   ```bash
   gcloud auth login company@cor-jp.com
   ```

2. フェーズ1スクリプトを実行:
   ```bash
   chmod +x phase1_download.sh
   ./phase1_download.sh
   ```

3. 以下の情報をメモ:
   - ダウンロードディレクトリのパス
   - 失敗したバケット（もしあれば）

**所要時間**: データ量とネットワーク速度に依存（数時間〜）

---

### 📦 フェーズ2: アーカイブ作成

**実行アカウント**: 不要（ローカル作業）

1. フェーズ2スクリプトを実行:
   ```bash
   chmod +x phase2_archive.sh
   ./phase2_archive.sh
   ```

2. フェーズ1で作成されたディレクトリパスを入力

3. 圧縮オプションを選択（通常は標準圧縮を推奨）

4. 作成されたアーカイブファイルのパスをメモ

**所要時間**: データ量に依存（30分〜数時間）

---

### ☁️ フェーズ3: アップロード

**実行アカウント**: `company@u-dake.com`

1. u-dake.comアカウントでログイン:
   ```bash
   gcloud auth login company@u-dake.com
   ```

2. フェーズ3スクリプトを実行:
   ```bash
   chmod +x phase3_upload.sh
   ./phase3_upload.sh
   ```

3. フェーズ2で作成されたアーカイブファイルのパスを入力

4. アップロード先の設定（デフォルト: `archive`バケット）

5. 並列アップロードの使用を推奨（大きなファイルの場合）

**所要時間**: ファイルサイズとネットワーク速度に依存

---

## トラブルシューティング

### ダウンロードが失敗する場合
```bash
# 個別のバケットを手動でダウンロード
gsutil -m cp -r gs://bucket-name/** /local/path/bucket-name/
```

### アップロードが中断される場合
```bash
# レジューム可能なアップロード
gsutil -o GSUtil:parallel_composite_upload_threshold=150M \
       cp -c archive.tar.gz gs://archive/
```

### 認証エラーの場合
```bash
# 認証情報のリフレッシュ
gcloud auth application-default login
gcloud auth list  # アクティブなアカウントを確認
```

## 復元方法

### アーカイブ全体の復元
```bash
# u-dakeプロジェクトから取得
gcloud config set project u-dake
gsutil cp gs://archive/yolov8environment_backup_*.tar.gz .
tar xzf yolov8environment_backup_*.tar.gz
```

### 特定のバケットのみ復元
```bash
# アーカイブ内容の確認
tar tzf archive.tar.gz | grep "bucket-name"

# 特定のバケットのみ展開
tar xzf archive.tar.gz --wildcards "*/bucket-name/*"
```

### 高度な復元（対話的）
```bash
# 復元スクリプトを使用
chmod +x advanced_restore.sh
./advanced_restore.sh
```

## セキュリティ考慮事項

1. **アクセス権限**: アーカイブはデフォルトでプロジェクト内のみアクセス可能
2. **暗号化**: GCSは保存時に自動的に暗号化
3. **監査ログ**: 両プロジェクトでアクセスログが記録される

## ディスク容量の見積もり

| データ量 | ダウンロード | アーカイブ（圧縮後） | 必要な空き容量 |
|---------|-------------|-------------------|---------------|
| 10 GB   | 10 GB       | 約 7 GB           | 20 GB以上     |
| 50 GB   | 50 GB       | 約 35 GB          | 100 GB以上    |
| 100 GB  | 100 GB      | 約 70 GB          | 200 GB以上    |

## チェックリスト

- [ ] cor-jp.comアカウントでのアクセス確認
- [ ] u-dake.comアカウントでのアクセス確認
- [ ] 十分なローカルディスク容量の確認
- [ ] 安定したネットワーク接続の確保
- [ ] フェーズ1: ダウンロード完了
- [ ] フェーズ2: アーカイブ作成完了
- [ ] フェーズ3: アップロード完了
- [ ] ローカルファイルのクリーンアップ
- [ ] 移行の検証（サンプルファイルの確認）

## サポート

問題が発生した場合は、各フェーズのログファイルを確認してください：
- フェーズ1: `download_progress.log`
- フェーズ2: ターミナル出力
- フェーズ3: gsutilのエラーメッセージ