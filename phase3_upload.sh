#!/bin/bash

# ===============================================
# フェーズ3: u-dakeプロジェクトへアップロード
# 実行前に: gcloud auth login company@u-dake.com
# ===============================================

set -euo pipefail

# 設定
DEST_PROJECT="u-dake"
ARCHIVE_BUCKET_NAME="archive"

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

# プログレス表示関数
show_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%$((50 - filled))s" | tr ' ' '-'
    printf "] %d%%" $percent
}

# メイン処理開始
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}        フェーズ3: u-dakeプロジェクトへアップロード${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 現在の認証情報確認
log_step "現在の認証情報を確認"
CURRENT_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)")
log_info "アクティブなアカウント: ${CURRENT_ACCOUNT}"

if [[ ! "$CURRENT_ACCOUNT" == *"u-dake.com"* ]]; then
    log_error "company@u-dake.com でログインする必要があります"
    echo ""
    echo "以下のコマンドを実行してください:"
    echo "  gcloud auth login company@u-dake.com"
    echo ""
    exit 1
fi

# プロジェクト設定
log_step "プロジェクトを設定"
gcloud config set project "$DEST_PROJECT" --quiet
log_info "プロジェクト: $(gcloud config get-value project)"

# アーカイブファイルの選択
log_step "アップロードするアーカイブファイルを選択"
echo "フェーズ2で作成したアーカイブファイル（.tar.gz）のパスを入力してください"
echo "例: /Users/teradakousuke/Library/Mobile Documents/com~apple~CloudDocs/Cor.inc/U-DAKE/GCS/yolov8environment_backup_20240115_123456.tar.gz"
echo ""
echo -n "アーカイブファイルのパス: "
read -r ARCHIVE_PATH

# ファイルの存在確認
if [ ! -f "$ARCHIVE_PATH" ]; then
    log_error "指定されたファイルが存在しません: ${ARCHIVE_PATH}"
    exit 1
fi

ARCHIVE_NAME=$(basename "$ARCHIVE_PATH")
ARCHIVE_SIZE_BYTES=$(stat -f%z "$ARCHIVE_PATH" 2>/dev/null || stat -c%s "$ARCHIVE_PATH" 2>/dev/null)
ARCHIVE_SIZE_HUMAN=$(du -h "$ARCHIVE_PATH" | cut -f1)

log_info "アーカイブファイル: ${ARCHIVE_NAME}"
log_info "ファイルサイズ: ${ARCHIVE_SIZE_HUMAN}"

# メタデータファイルの確認
METADATA_PATH="${ARCHIVE_PATH%.tar.gz}_metadata.json"
if [ -f "$METADATA_PATH" ]; then
    log_info "✓ メタデータファイルを検出: $(basename "$METADATA_PATH")"
else
    log_warn "メタデータファイルが見つかりません"
fi

# アップロード先バケットの設定
log_step "アップロード先の設定"
echo "デフォルトのバケット名: ${ARCHIVE_BUCKET_NAME}"
echo -n "別のバケット名を使用しますか？ (y/N): "
read -r CHANGE_BUCKET

if [[ $CHANGE_BUCKET =~ ^[Yy]$ ]]; then
    echo -n "バケット名を入力: "
    read -r ARCHIVE_BUCKET_NAME
fi

# バケットの存在確認・作成
log_info "バケット gs://${ARCHIVE_BUCKET_NAME} を確認中..."
if ! gsutil ls "gs://${ARCHIVE_BUCKET_NAME}" &>/dev/null; then
    log_info "バケットが存在しません。作成しますか？"
    echo -n "(y/N): "
    read -r CREATE_BUCKET
    
    if [[ $CREATE_BUCKET =~ ^[Yy]$ ]]; then
        log_info "バケットを作成中..."
        # リージョンの選択
        echo "バケットのリージョンを選択:"
        echo "1) asia-northeast1 (東京)"
        echo "2) asia-northeast2 (大阪)"
        echo "3) us-central1 (アイオワ)"
        echo "4) multi-region asia"
        echo -n "選択 (1-4) [1]: "
        read -r REGION_CHOICE
        
        case "${REGION_CHOICE:-1}" in
            1) LOCATION="asia-northeast1" ;;
            2) LOCATION="asia-northeast2" ;;
            3) LOCATION="us-central1" ;;
            4) LOCATION="asia" ;;
            *) LOCATION="asia-northeast1" ;;
        esac
        
        if gsutil mb -p "$DEST_PROJECT" -l "$LOCATION" "gs://${ARCHIVE_BUCKET_NAME}"; then
            log_info "✓ バケット作成完了"
        else
            log_error "バケットの作成に失敗しました"
            exit 1
        fi
    else
        log_error "処理を中止しました"
        exit 1
    fi
fi

# アップロード実行
log_step "アップロードを開始"
log_info "アップロード先: gs://${ARCHIVE_BUCKET_NAME}/${ARCHIVE_NAME}"

# アップロード設定
echo "大きなファイルのアップロードには時間がかかります"
echo "並列アップロードを使用して高速化できます"
echo -n "並列アップロードを有効にしますか？ (Y/n): "
read -r USE_PARALLEL

UPLOAD_START=$(date +%s)

if [[ ! $USE_PARALLEL =~ ^[Nn]$ ]]; then
    # 並列アップロード（150MB以上のファイルを分割）
    log_info "並列アップロードを実行中..."
    gsutil -o GSUtil:parallel_composite_upload_threshold=150M \
           -o GSUtil:parallel_composite_upload_component_size=50M \
           cp "$ARCHIVE_PATH" "gs://${ARCHIVE_BUCKET_NAME}/${ARCHIVE_NAME}"
else
    # 通常のアップロード
    log_info "通常アップロードを実行中..."
    gsutil cp "$ARCHIVE_PATH" "gs://${ARCHIVE_BUCKET_NAME}/${ARCHIVE_NAME}"
fi

UPLOAD_END=$(date +%s)
UPLOAD_TIME=$((UPLOAD_END - UPLOAD_START))

if [ $? -eq 0 ]; then
    log_info "✓ アップロード完了（所要時間: $((UPLOAD_TIME / 60))分 $((UPLOAD_TIME % 60))秒）"
else
    log_error "アップロードに失敗しました"
    exit 1
fi

# アップロードの検証
log_step "アップロードを検証"
REMOTE_SIZE=$(gsutil du "gs://${ARCHIVE_BUCKET_NAME}/${ARCHIVE_NAME}" 2>/dev/null | awk '{print $1}')

if [ "$REMOTE_SIZE" -eq "$ARCHIVE_SIZE_BYTES" ]; then
    log_info "✓ ファイルサイズ検証: OK"
else
    log_warn "⚠ ファイルサイズが一致しません"
    log_warn "  ローカル: ${ARCHIVE_SIZE_BYTES} bytes"
    log_warn "  リモート: ${REMOTE_SIZE} bytes"
fi

# メタデータのアップロード
if [ -f "$METADATA_PATH" ]; then
    log_step "メタデータをアップロード"
    METADATA_NAME=$(basename "$METADATA_PATH")
    
    if gsutil cp "$METADATA_PATH" "gs://${ARCHIVE_BUCKET_NAME}/${METADATA_NAME}"; then
        log_info "✓ メタデータアップロード完了"
    else
        log_warn "メタデータのアップロードに失敗しました"
    fi
fi

# 最終確認とサマリー
log_step "移行完了サマリー"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ すべての処理が完了しました！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "アップロード先:"
echo "  アーカイブ: gs://${ARCHIVE_BUCKET_NAME}/${ARCHIVE_NAME}"
if [ -f "$METADATA_PATH" ]; then
    echo "  メタデータ: gs://${ARCHIVE_BUCKET_NAME}/${METADATA_NAME}"
fi
echo ""
echo "アップロード統計:"
echo "  ファイルサイズ: ${ARCHIVE_SIZE_HUMAN}"
echo "  所要時間: $((UPLOAD_TIME / 60))分 $((UPLOAD_TIME % 60))秒"
echo "  転送速度: $(echo "scale=2; $ARCHIVE_SIZE_BYTES / $UPLOAD_TIME / 1024 / 1024" | bc) MB/s"

# オプション: アクセス権限の設定
echo ""
echo -e "${YELLOW}オプション: アクセス権限の設定${NC}"
echo "アーカイブへのアクセス権限を設定しますか？"
echo "1) プロジェクト内のみアクセス可能（デフォルト）"
echo "2) 特定のユーザー/グループに読み取り権限を付与"
echo "3) スキップ"
echo -n "選択 (1-3) [3]: "
read -r PERMISSION_CHOICE

case "${PERMISSION_CHOICE:-3}" in
    2)
        echo -n "アクセスを許可するメールアドレス（カンマ区切り）: "
        read -r ALLOWED_USERS
        
        IFS=',' read -ra USERS <<< "$ALLOWED_USERS"
        for USER in "${USERS[@]}"; do
            USER=$(echo "$USER" | xargs)  # trim whitespace
            log_info "権限を付与: ${USER}"
            gsutil acl ch -u "${USER}:R" "gs://${ARCHIVE_BUCKET_NAME}/${ARCHIVE_NAME}"
        done
        ;;
esac

# ローカルファイルの削除オプション
echo ""
echo -e "${YELLOW}クリーンアップ${NC}"
echo "ローカルのアーカイブファイルを削除してディスク容量を解放しますか？"
echo "（GCSにアップロード済みのため、ローカルコピーは不要かもしれません）"
echo -n "(y/N): "
read -r DELETE_LOCAL

if [[ $DELETE_LOCAL =~ ^[Yy]$ ]]; then
    log_info "ローカルファイルを削除中..."
    rm -f "$ARCHIVE_PATH"
    [ -f "$METADATA_PATH" ] && rm -f "$METADATA_PATH"
    log_info "✓ 削除完了"
fi

echo ""
echo -e "${GREEN}移行プロジェクトが完了しました！${NC}"