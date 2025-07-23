#!/bin/bash

# ===============================================
# 移行ステータスチェックスクリプト
# ===============================================

set -euo pipefail

# 環境変数の読み込み
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== GCS移行ステータス確認 ===${NC}"
echo ""

# 環境変数のチェック
echo -e "${GREEN}▶ 環境変数の設定状況:${NC}"
echo -n "  GCS_SOURCE_ACCOUNT: "
[ -n "${GCS_SOURCE_ACCOUNT:-}" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
echo -n "  GCS_DEST_ACCOUNT: "
[ -n "${GCS_DEST_ACCOUNT:-}" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
echo -n "  GCS_SOURCE_PROJECT: "
[ -n "${GCS_SOURCE_PROJECT:-}" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
echo -n "  GCS_DEST_PROJECT: "
[ -n "${GCS_DEST_PROJECT:-}" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
echo -n "  GCS_LOCAL_BACKUP_DIR: "
[ -n "${GCS_LOCAL_BACKUP_DIR:-}" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
echo -n "  GCS_ARCHIVE_BUCKET: "
[ -n "${GCS_ARCHIVE_BUCKET:-}" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
echo ""

# 認証状態のチェック
echo -e "${GREEN}▶ 現在の認証状態:${NC}"
CURRENT_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)")
echo "  アクティブアカウント: ${CURRENT_ACCOUNT}"
echo ""

# ソースプロジェクトのバケット数確認
echo -e "${GREEN}▶ ソースプロジェクトのバケット数:${NC}"
if [ "${CURRENT_ACCOUNT}" = "${GCS_SOURCE_ACCOUNT}" ]; then
    BUCKET_COUNT=$(gsutil ls -p "${GCS_SOURCE_PROJECT}" 2>/dev/null | wc -l | tr -d ' ')
    echo "  ${BUCKET_COUNT} 個のバケット"
else
    echo "  ${YELLOW}(ソースアカウントに切り替えが必要)${NC}"
fi
echo ""

# 最新のバックアップ状態
echo -e "${GREEN}▶ 最新のバックアップ:${NC}"
if [ -f "${GCS_LOCAL_BACKUP_DIR}/latest_backup_path.txt" ]; then
    LATEST_PATH=$(cat "${GCS_LOCAL_BACKUP_DIR}/latest_backup_path.txt")
    echo "  パス: ${LATEST_PATH}"
    
    if [ -d "$LATEST_PATH" ]; then
        # サマリーファイルがある場合
        if [ -f "${LATEST_PATH}/download_summary.txt" ]; then
            echo ""
            echo "  ${BLUE}ダウンロードサマリー:${NC}"
            grep -E "総バケット数:|成功:|空のバケット:|失敗:" "${LATEST_PATH}/download_summary.txt" | sed 's/^/    /'
        fi
        
        # サイズ
        BACKUP_SIZE=$(du -sh "$LATEST_PATH" 2>/dev/null | cut -f1)
        echo "  サイズ: ${BACKUP_SIZE}"
    else
        echo "  ${RED}バックアップディレクトリが見つかりません${NC}"
    fi
else
    echo "  ${YELLOW}まだバックアップが作成されていません${NC}"
fi
echo ""

# アーカイブの確認
echo -e "${GREEN}▶ アーカイブファイル:${NC}"
if [ -d "${GCS_LOCAL_BACKUP_DIR}" ]; then
    ARCHIVES=$(find "${GCS_LOCAL_BACKUP_DIR}" -name "*.tar.gz" -type f 2>/dev/null | head -5)
    if [ -n "$ARCHIVES" ]; then
        echo "$ARCHIVES" | while read -r archive; do
            SIZE=$(du -h "$archive" | cut -f1)
            echo "  $(basename "$archive") (${SIZE})"
        done
    else
        echo "  ${YELLOW}アーカイブファイルがありません${NC}"
    fi
else
    echo "  ${YELLOW}バックアップディレクトリが設定されていません${NC}"
fi
echo ""

# 推奨アクション
echo -e "${BLUE}▶ 推奨アクション:${NC}"
if [ ! -f "${GCS_LOCAL_BACKUP_DIR}/latest_backup_path.txt" ]; then
    echo "  1. ${YELLOW}make robust-download${NC} - バケットをダウンロード"
    echo "  2. ${YELLOW}make phase2${NC} - アーカイブ作成"
    echo "  3. ${YELLOW}make phase3${NC} - アップロード"
else
    if [ -z "$(find "${GCS_LOCAL_BACKUP_DIR}" -name "*.tar.gz" -type f 2>/dev/null | head -1)" ]; then
        echo "  1. ${YELLOW}make phase2${NC} - アーカイブ作成"
        echo "  2. ${YELLOW}make phase3${NC} - アップロード"
    else
        echo "  1. ${YELLOW}make phase3${NC} - アップロード"
    fi
fi
echo ""
echo "完全な移行を実行するには: ${GREEN}make migrate-robust${NC}"