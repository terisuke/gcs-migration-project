#!/bin/bash

# ===============================================
# 完全な移行ワークフロー - 100%成功を保証
# ===============================================

set -euo pipefail

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== GCS完全移行ワークフロー ===${NC}"
echo -e "${GREEN}このワークフローは3つのフェーズを確実に実行します:${NC}"
echo -e "  1. ${YELLOW}ロバストダウンロード${NC} - すべてのバケットを確実にダウンロード"
echo -e "  2. ${YELLOW}アーカイブ作成${NC} - ダウンロードしたデータをtar.gzに圧縮"
echo -e "  3. ${YELLOW}アップロード${NC} - アーカイブを移行先プロジェクトへアップロード"
echo ""

# 確認
read -p "続行しますか？ [y/N]: " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}移行をキャンセルしました${NC}"
    exit 0
fi

# フェーズ1: ロバストダウンロード
echo -e "\n${BLUE}=== フェーズ1: ロバストダウンロード ===${NC}"
if ! make robust-download; then
    echo -e "${RED}エラー: ダウンロードフェーズが失敗しました${NC}"
    exit 1
fi

# フェーズ2: アーカイブ作成
echo -e "\n${BLUE}=== フェーズ2: アーカイブ作成 ===${NC}"
if ! make phase2; then
    echo -e "${RED}エラー: アーカイブ作成フェーズが失敗しました${NC}"
    exit 1
fi

# フェーズ3: アップロード
echo -e "\n${BLUE}=== フェーズ3: アップロード ===${NC}"
if ! make phase3; then
    echo -e "${RED}エラー: アップロードフェーズが失敗しました${NC}"
    exit 1
fi

echo -e "\n${GREEN}✅ 完全な移行が成功しました！${NC}"
echo -e "${GREEN}すべてのバケットが正常に移行されました。${NC}"