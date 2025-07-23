#!/bin/bash

# 残りのバケットをダウンロードするスクリプト

set -euo pipefail

# 環境変数の読み込み
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# カラー定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 既存のバックアップディレクトリを使用
WORK_DIR="/Users/teradakousuke/Library/Mobile Documents/com~apple~CloudDocs/Cor.inc/U-DAKE/GCS/yolov8environment_backup_20250723_121435"
PROGRESS_LOG="${WORK_DIR}/download_progress.log"

echo -e "${BLUE}残りのバケットをダウンロード中...${NC}"

# 残りのバケットリスト
REMAINING_BUCKETS=(
    "gs://pdf-bulk-converter-test/"
    "gs://pdf-to-image-513507930971/"
    "gs://run-sources-yolov8environment-asia-northeast1/"
    "gs://yolo-v11-training/"
    "gs://yolo-v11-training-staging/"
    "gs://yolov8environment-logs/"
    "gs://yolov8environment_cloudbuild/"
)

# 各バケットをダウンロード
for BUCKET_URL in "${REMAINING_BUCKETS[@]}"; do
    BUCKET_NAME=$(basename "${BUCKET_URL%/}")
    echo -e "${GREEN}[INFO]${NC} ダウンロード中: ${BUCKET_NAME}"
    
    BUCKET_DIR="${WORK_DIR}/${BUCKET_NAME}"
    mkdir -p "$BUCKET_DIR"
    
    # ダウンロード実行（エラーがあっても続行）
    if gsutil -o "GSUtil:parallel_process_count=1" -m cp -r "${BUCKET_URL}**" "$BUCKET_DIR/" 2>&1 | tee -a "$PROGRESS_LOG"; then
        echo "SUCCESS: ${BUCKET_NAME}" >> "${WORK_DIR}/download_status.txt"
        echo -e "${GREEN}✓ 完了: ${BUCKET_NAME}${NC}"
    else
        echo "FAILED: ${BUCKET_NAME}" >> "${WORK_DIR}/download_status.txt"
        echo -e "${YELLOW}✗ 失敗: ${BUCKET_NAME}${NC}"
    fi
done

echo -e "${GREEN}残りのバケットのダウンロードが完了しました${NC}"