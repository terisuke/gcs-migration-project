#!/bin/bash

# ===============================================
# フェーズ1: ソースプロジェクトからローカルへダウンロード
# ===============================================

set -euo pipefail

# 環境変数の読み込み
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# 環境変数チェック
if [ -z "${GCS_SOURCE_ACCOUNT:-}" ] || [ -z "${GCS_SOURCE_PROJECT:-}" ] || [ -z "${GCS_LOCAL_BACKUP_DIR:-}" ]; then
    echo "Error: Required environment variables are not set."
    echo "Please ensure the following variables are set in .env file:"
    echo "  - GCS_SOURCE_ACCOUNT"
    echo "  - GCS_SOURCE_PROJECT"
    echo "  - GCS_LOCAL_BACKUP_DIR"
    exit 1
fi

# 設定
SOURCE_PROJECT="${GCS_SOURCE_PROJECT}"
LOCAL_DOWNLOAD_DIR="${GCS_LOCAL_BACKUP_DIR}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
WORK_DIR="${LOCAL_DOWNLOAD_DIR}/${SOURCE_PROJECT}_backup_${TIMESTAMP}"

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ログ関数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}▶ $1${NC}"
}

# メイン処理開始
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}   フェーズ1: ${SOURCE_PROJECT} からローカルへダウンロード${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 現在の認証情報確認
log_step "現在の認証情報を確認"
CURRENT_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)")
log_info "アクティブなアカウント: ${CURRENT_ACCOUNT}"

if [[ "$CURRENT_ACCOUNT" != "$GCS_SOURCE_ACCOUNT" ]]; then
    log_error "${GCS_SOURCE_ACCOUNT} でログインする必要があります"
    echo ""
    echo "以下のコマンドを実行してください:"
    echo "  gcloud auth login ${GCS_SOURCE_ACCOUNT}"
    echo "  または"
    echo "  make auth-source"
    echo ""
    exit 1
fi

# プロジェクト設定
log_step "プロジェクトを設定"
gcloud config set project "$SOURCE_PROJECT" --quiet
log_info "プロジェクト: $(gcloud config get-value project)"

# ローカルディレクトリの準備
log_step "ローカルディレクトリを準備"
mkdir -p "$WORK_DIR"
log_info "作業ディレクトリ: ${WORK_DIR}"

# バケット一覧取得
log_step "バケット一覧を取得"
BUCKETS=$(gsutil ls -p "$SOURCE_PROJECT" 2>/dev/null || echo "")

if [ -z "$BUCKETS" ]; then
    log_error "バケットが見つかりませんでした"
    exit 1
fi

BUCKET_COUNT=$(echo "$BUCKETS" | wc -l | tr -d ' ')
log_info "見つかったバケット数: ${BUCKET_COUNT}"

# バケット情報をファイルに保存
MANIFEST_FILE="${WORK_DIR}/download_manifest.txt"
echo "$BUCKETS" > "$MANIFEST_FILE"

# 容量見積もり（オプション）
log_step "データ容量を見積もり中（スキップする場合は Ctrl+C）"
echo "注意: 大量のデータがある場合、この処理には時間がかかります"
echo -n "続行しますか？ (y/N): "
read -r ESTIMATE_CHOICE

TOTAL_SIZE=0
if [[ $ESTIMATE_CHOICE =~ ^[Yy]$ ]]; then
    for BUCKET_URL in $BUCKETS; do
        log_info "容量確認中: ${BUCKET_URL}"
        SIZE=$(gsutil du -s "$BUCKET_URL" 2>/dev/null | awk '{print $1}' || echo "0")
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
    done
    
    TOTAL_SIZE_GB=$((TOTAL_SIZE / 1024 / 1024 / 1024 + 1))
    log_info "推定総容量: 約 ${TOTAL_SIZE_GB} GB"
    
    # ディスク容量確認
    AVAILABLE_GB=$(df -BG "$LOCAL_DOWNLOAD_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    log_info "利用可能なディスク容量: ${AVAILABLE_GB} GB"
    
    if [ "$AVAILABLE_GB" -lt "$((TOTAL_SIZE_GB * 2))" ]; then
        log_warn "ディスク容量が不足している可能性があります"
    fi
fi

# ダウンロード実行
log_step "ダウンロードを開始"
echo "バケットリスト:"
echo "$BUCKETS" | nl

echo ""
echo -n "すべてのバケットをダウンロードしますか？ (y/N): "
read -r DOWNLOAD_ALL

if [[ ! $DOWNLOAD_ALL =~ ^[Yy]$ ]]; then
    log_info "処理を中止しました"
    exit 0
fi

# 進捗ログファイル
PROGRESS_LOG="${WORK_DIR}/download_progress.log"
echo "Download started at: $(date)" > "$PROGRESS_LOG"

# 各バケットをダウンロード
CURRENT=0
FAILED_BUCKETS=""

for BUCKET_URL in $BUCKETS; do
    CURRENT=$((CURRENT + 1))
    BUCKET_NAME=$(basename "${BUCKET_URL%/}")
    
    echo "" | tee -a "$PROGRESS_LOG"
    log_info "[${CURRENT}/${BUCKET_COUNT}] バケット: ${BUCKET_NAME}" | tee -a "$PROGRESS_LOG"
    
    BUCKET_DIR="${WORK_DIR}/${BUCKET_NAME}"
    mkdir -p "$BUCKET_DIR"
    
    # ダウンロード実行
    if gsutil -o "GSUtil:parallel_process_count=1" -m cp -r "${BUCKET_URL}**" "$BUCKET_DIR/" 2>&1 | tee -a "$PROGRESS_LOG"; then
        log_info "✓ 完了: ${BUCKET_NAME}" | tee -a "$PROGRESS_LOG"
        echo "SUCCESS: ${BUCKET_NAME}" >> "${WORK_DIR}/download_status.txt"
    else
        log_warn "✗ 失敗: ${BUCKET_NAME}" | tee -a "$PROGRESS_LOG"
        echo "FAILED: ${BUCKET_NAME}" >> "${WORK_DIR}/download_status.txt"
        FAILED_BUCKETS="${FAILED_BUCKETS}${BUCKET_NAME}\n"
    fi
done

# 結果サマリー
log_step "ダウンロード完了"
echo ""
log_info "作業ディレクトリ: ${WORK_DIR}"
log_info "ダウンロードログ: ${PROGRESS_LOG}"
log_info "ステータスファイル: ${WORK_DIR}/download_status.txt"

if [ -n "$FAILED_BUCKETS" ]; then
    log_warn "失敗したバケット:"
    echo -e "$FAILED_BUCKETS"
fi

# 次のステップの案内
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}次のステップ:${NC}"
echo -e "${YELLOW}1. このディレクトリパスをメモしてください:${NC}"
echo -e "   ${BLUE}${WORK_DIR}${NC}"
echo -e "${YELLOW}2. フェーズ2のスクリプトを実行してアーカイブを作成します${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"