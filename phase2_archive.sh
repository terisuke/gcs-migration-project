#!/bin/bash

# ===============================================
# フェーズ2: ローカルでアーカイブ作成
# 認証不要 - ローカルファイル操作のみ
# ===============================================

set -euo pipefail

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
echo -e "${BLUE}          フェーズ2: ローカルでアーカイブ作成${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ダウンロードディレクトリの確認
log_step "フェーズ1でダウンロードしたディレクトリを指定"
echo "例: /Users/teradakousuke/Library/Mobile Documents/com~apple~CloudDocs/Cor.inc/U-DAKE/GCS/yolov8environment_backup_20240115_123456"
echo ""
echo -n "ディレクトリパスを入力: "
read -r WORK_DIR

# ディレクトリの存在確認
if [ ! -d "$WORK_DIR" ]; then
    log_error "指定されたディレクトリが存在しません: ${WORK_DIR}"
    exit 1
fi

# ダウンロードステータスの確認
if [ -f "${WORK_DIR}/download_status.txt" ]; then
    log_info "ダウンロードステータスを確認"
    SUCCESS_COUNT=$(grep -c "SUCCESS:" "${WORK_DIR}/download_status.txt" || echo "0")
    FAILED_COUNT=$(grep -c "FAILED:" "${WORK_DIR}/download_status.txt" || echo "0")
    
    log_info "成功: ${SUCCESS_COUNT} バケット"
    if [ "$FAILED_COUNT" -gt 0 ]; then
        log_warn "失敗: ${FAILED_COUNT} バケット"
        echo "失敗したバケット:"
        grep "FAILED:" "${WORK_DIR}/download_status.txt" | sed 's/FAILED: /  - /'
    fi
fi

# ディレクトリサイズの確認
log_step "データサイズを確認"
TOTAL_SIZE=$(du -sh "$WORK_DIR" | cut -f1)
log_info "総データサイズ: ${TOTAL_SIZE}"

# アーカイブ作成の準備
PARENT_DIR=$(dirname "$WORK_DIR")
BACKUP_NAME=$(basename "$WORK_DIR")
ARCHIVE_NAME="${BACKUP_NAME}.tar.gz"
ARCHIVE_PATH="${PARENT_DIR}/${ARCHIVE_NAME}"

# 既存アーカイブの確認
if [ -f "$ARCHIVE_PATH" ]; then
    log_warn "既存のアーカイブファイルが見つかりました: ${ARCHIVE_NAME}"
    echo -n "上書きしますか？ (y/N): "
    read -r OVERWRITE
    if [[ ! $OVERWRITE =~ ^[Yy]$ ]]; then
        log_info "処理を中止しました"
        exit 0
    fi
fi

# 圧縮オプションの選択
log_step "圧縮オプションを選択"
echo "1) 高速圧縮（圧縮率: 低、速度: 速い）"
echo "2) 標準圧縮（圧縮率: 中、速度: 普通）※推奨"
echo "3) 最大圧縮（圧縮率: 高、速度: 遅い）"
echo -n "選択 (1-3) [2]: "
read -r COMPRESS_OPTION

case "${COMPRESS_OPTION:-2}" in
    1) GZIP_LEVEL=1 ;;
    3) GZIP_LEVEL=9 ;;
    *) GZIP_LEVEL=6 ;;
esac

# アーカイブ作成
log_step "アーカイブを作成中"
log_info "これには時間がかかる場合があります..."
log_info "アーカイブ名: ${ARCHIVE_NAME}"
log_info "圧縮レベル: ${GZIP_LEVEL}"

cd "$PARENT_DIR"

# プログレス表示付きでtar実行
if command -v pv >/dev/null 2>&1; then
    # pvコマンドがある場合はプログレスバー表示
    tar cf - "$BACKUP_NAME" | pv -s $(du -sb "$BACKUP_NAME" | awk '{print $1}') | gzip -${GZIP_LEVEL} > "$ARCHIVE_NAME"
else
    # pvがない場合は進捗ドット表示
    tar czf "$ARCHIVE_NAME" "$BACKUP_NAME" --checkpoint=1000 --checkpoint-action=dot --gzip-compression-level=${GZIP_LEVEL}
    echo ""
fi

# アーカイブの検証
log_step "アーカイブを検証"
if [ -f "$ARCHIVE_PATH" ]; then
    ARCHIVE_SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1)
    log_info "✓ アーカイブ作成成功"
    log_info "アーカイブサイズ: ${ARCHIVE_SIZE}"
    
    # 圧縮率の計算
    ORIGINAL_BYTES=$(du -sb "$WORK_DIR" | cut -f1)
    ARCHIVE_BYTES=$(stat -f%z "$ARCHIVE_PATH" 2>/dev/null || stat -c%s "$ARCHIVE_PATH" 2>/dev/null)
    COMPRESSION_RATIO=$(echo "scale=2; 100 - ($ARCHIVE_BYTES * 100 / $ORIGINAL_BYTES)" | bc)
    log_info "圧縮率: ${COMPRESSION_RATIO}%"
else
    log_error "アーカイブの作成に失敗しました"
    exit 1
fi

# メタデータファイルの作成
log_step "メタデータファイルを作成"
METADATA_FILE="${PARENT_DIR}/${BACKUP_NAME}_metadata.json"

# バケット一覧を取得
BUCKET_LIST=$(find "$WORK_DIR" -maxdepth 1 -type d -not -path "$WORK_DIR" -exec basename {} \; | sort)

cat > "$METADATA_FILE" <<EOF
{
  "archive_info": {
    "name": "${ARCHIVE_NAME}",
    "path": "${ARCHIVE_PATH}",
    "size_bytes": ${ARCHIVE_BYTES},
    "size_human": "${ARCHIVE_SIZE}",
    "compression_ratio": "${COMPRESSION_RATIO}%",
    "compression_level": ${GZIP_LEVEL},
    "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "source_directory": "${WORK_DIR}",
    "original_size_bytes": ${ORIGINAL_BYTES},
    "original_size_human": "${TOTAL_SIZE}"
  },
  "source_project": "yolov8environment",
  "bucket_count": $(echo "$BUCKET_LIST" | wc -l | tr -d ' '),
  "buckets": [
$(echo "$BUCKET_LIST" | awk '{printf "    \"%s\"", $0}' | sed '$!s/$/,/')
  ]
}
EOF

log_info "✓ メタデータファイル作成: ${METADATA_FILE}"

# クリーンアップオプション
log_step "クリーンアップオプション"
echo "元のダウンロードデータを削除してディスク容量を節約できます"
echo "（アーカイブは保持されます）"
echo ""
echo -n "ダウンロードデータを削除しますか？ (y/N): "
read -r DELETE_ORIGINAL

if [[ $DELETE_ORIGINAL =~ ^[Yy]$ ]]; then
    log_info "元データを削除中..."
    rm -rf "$WORK_DIR"
    log_info "✓ 削除完了"
fi

# 次のステップの案内
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ フェーズ2完了！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}作成されたファイル:${NC}"
echo -e "  アーカイブ: ${BLUE}${ARCHIVE_PATH}${NC}"
echo -e "  メタデータ: ${BLUE}${METADATA_FILE}${NC}"
echo ""
echo -e "${YELLOW}次のステップ:${NC}"
echo -e "${YELLOW}1. company@u-dake.com でログイン:${NC}"
echo -e "   ${BLUE}gcloud auth login company@u-dake.com${NC}"
echo -e "${YELLOW}2. フェーズ3のスクリプトを実行してu-dakeプロジェクトにアップロード${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"