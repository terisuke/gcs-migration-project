#!/bin/bash

# ===============================================
# 高度な復元スクリプト
# デスティネーションプロジェクトのアーカイブから柔軟に復元
# ===============================================

set -euo pipefail

# 環境変数の読み込み
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# 設定 (環境変数から取得、またはデフォルト値を使用)
ARCHIVE_PROJECT="${GCS_DEST_PROJECT:-u-dake}"
ARCHIVE_BUCKET="${GCS_ARCHIVE_BUCKET:-archive}"
DEFAULT_RESTORE_DIR="${GCS_RESTORE_DIR:-/tmp/gcs_restore}"

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# ヘルプ表示
show_help() {
    cat << EOF
${CYAN}GCS アーカイブ復元ツール${NC}

使用方法:
  $0 [オプション]

オプション:
  -h, --help              このヘルプを表示
  -p, --project PROJECT   ソースプロジェクト (デフォルト: ${ARCHIVE_PROJECT})
  -b, --bucket BUCKET     アーカイブバケット (デフォルト: ${ARCHIVE_BUCKET})
  -d, --dir DIR          復元先ディレクトリ (デフォルト: ${DEFAULT_RESTORE_DIR})
  -l, --list             アーカイブ一覧を表示して終了
  -a, --archive NAME     指定したアーカイブを使用（対話モードをスキップ）

例:
  # 対話モードで復元
  $0

  # アーカイブ一覧を表示
  $0 --list

  # 特定のアーカイブを指定ディレクトリに復元
  $0 --archive ${GCS_SOURCE_PROJECT:-project}_backup_20240115.tar.gz --dir /data/restore

EOF
}

# オプション解析
PROJECT="$ARCHIVE_PROJECT"
BUCKET="$ARCHIVE_BUCKET"
RESTORE_DIR="$DEFAULT_RESTORE_DIR"
LIST_ONLY=false
ARCHIVE_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--project)
            PROJECT="$2"
            shift 2
            ;;
        -b|--bucket)
            BUCKET="$2"
            shift 2
            ;;
        -d|--dir)
            RESTORE_DIR="$2"
            shift 2
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -a|--archive)
            ARCHIVE_NAME="$2"
            shift 2
            ;;
        *)
            log_error "不明なオプション: $1"
            show_help
            exit 1
            ;;
    esac
done

# メイン処理開始
clear
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}              GCS アーカイブ復元ツール${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# プロジェクト設定
log_step "プロジェクトを設定"
gcloud config set project "$PROJECT" --quiet
log_info "プロジェクト: $(gcloud config get-value project)"
log_info "バケット: gs://${BUCKET}"

# アーカイブ一覧取得
log_step "アーカイブ一覧を取得"
ARCHIVES=$(gsutil ls "gs://${BUCKET}/*.tar.gz" 2>/dev/null || echo "")

if [ -z "$ARCHIVES" ]; then
    log_error "アーカイブが見つかりませんでした"
    exit 1
fi

# 一覧表示モード
if [ "$LIST_ONLY" = true ]; then
    echo -e "\n${CYAN}利用可能なアーカイブ:${NC}"
    echo "$ARCHIVES" | while read -r ARCHIVE; do
        NAME=$(basename "$ARCHIVE")
        SIZE=$(gsutil du -h "$ARCHIVE" 2>/dev/null | awk '{print $1}')
        METADATA="${ARCHIVE%.tar.gz}_metadata.json"
        
        echo -e "\n${YELLOW}📦 $NAME${NC}"
        echo "   サイズ: $SIZE"
        
        # メタデータがある場合は詳細表示
        if gsutil ls "$METADATA" &>/dev/null; then
            echo "   メタデータ: あり"
            # メタデータの内容を取得して表示
            TEMP_META=$(mktemp)
            if gsutil cp "$METADATA" "$TEMP_META" &>/dev/null; then
                BUCKET_COUNT=$(jq -r '.bucket_count // "不明"' "$TEMP_META" 2>/dev/null)
                SOURCE_PROJECT=$(jq -r '.source_project // "不明"' "$TEMP_META" 2>/dev/null)
                echo "   ソースプロジェクト: $SOURCE_PROJECT"
                echo "   バケット数: $BUCKET_COUNT"
                rm -f "$TEMP_META"
            fi
        fi
    done
    exit 0
fi

# アーカイブ選択
if [ -z "$ARCHIVE_NAME" ]; then
    echo -e "\n${CYAN}利用可能なアーカイブ:${NC}"
    echo "$ARCHIVES" | nl
    echo -n "復元するアーカイブの番号を入力: "
    read -r ARCHIVE_NUM
    ARCHIVE_PATH=$(echo "$ARCHIVES" | sed -n "${ARCHIVE_NUM}p")
    ARCHIVE_NAME=$(basename "$ARCHIVE_PATH")
else
    ARCHIVE_PATH="gs://${BUCKET}/${ARCHIVE_NAME}"
fi

log_info "選択されたアーカイブ: ${ARCHIVE_NAME}"

# 復元ディレクトリの準備
mkdir -p "$RESTORE_DIR"
cd "$RESTORE_DIR"

# 復元モードの選択
echo -e "\n${CYAN}復元モード:${NC}"
echo "1) 📂 全体を復元"
echo "2) 🗂  特定のバケットを復元"
echo "3) 📄 特定のファイルを検索して復元"
echo "4) 🔍 アーカイブ内容をプレビュー"
echo -n "選択 (1-4): "
read -r MODE

case $MODE in
    1)
        # 全体復元
        log_step "アーカイブ全体を復元"
        log_info "ダウンロード中..."
        
        if gsutil cp "$ARCHIVE_PATH" . ; then
            log_info "展開中..."
            tar xzf "$ARCHIVE_NAME" --checkpoint=1000 --checkpoint-action=dot
            echo ""
            log_info "✓ 復元完了: ${RESTORE_DIR}"
            
            # 復元内容のサマリー
            EXTRACTED_DIR=$(tar tzf "$ARCHIVE_NAME" | head -1 | cut -d'/' -f1)
            if [ -d "$EXTRACTED_DIR" ]; then
                BUCKET_COUNT=$(find "$EXTRACTED_DIR" -maxdepth 1 -type d -not -path "$EXTRACTED_DIR" | wc -l)
                TOTAL_SIZE=$(du -sh "$EXTRACTED_DIR" | cut -f1)
                log_info "復元されたバケット数: $BUCKET_COUNT"
                log_info "総サイズ: $TOTAL_SIZE"
            fi
        else
            log_error "ダウンロードに失敗しました"
            exit 1
        fi
        ;;
        
    2)
        # 特定バケットの復元
        log_step "特定のバケットを復元"
        log_info "アーカイブ内のバケット一覧を取得中..."
        
        # 一時的にアーカイブをストリーミングで読み込み
        BUCKETS=$(gsutil cp "$ARCHIVE_PATH" - | tar tzf - | grep -E "^[^/]+/[^/]+/$" | cut -d'/' -f2 | sort -u)
        
        if [ -z "$BUCKETS" ]; then
            log_error "バケットが見つかりませんでした"
            exit 1
        fi
        
        echo -e "\n${CYAN}利用可能なバケット:${NC}"
        echo "$BUCKETS" | nl
        
        echo -n "復元するバケットの番号（複数可、カンマ区切り）: "
        read -r BUCKET_NUMS
        
        # アーカイブをダウンロード
        log_info "アーカイブをダウンロード中..."
        gsutil cp "$ARCHIVE_PATH" .
        
        # 選択されたバケットを復元
        IFS=',' read -ra NUMS <<< "$BUCKET_NUMS"
        for NUM in "${NUMS[@]}"; do
            NUM=$(echo "$NUM" | xargs)  # trim
            BUCKET_NAME=$(echo "$BUCKETS" | sed -n "${NUM}p")
            if [ -n "$BUCKET_NAME" ]; then
                log_info "復元中: $BUCKET_NAME"
                tar xzf "$ARCHIVE_NAME" --wildcards "*/${BUCKET_NAME}/*"
            fi
        done
        
        log_info "✓ 選択されたバケットの復元完了"
        ;;
        
    3)
        # ファイル検索と復元
        log_step "ファイルを検索して復元"
        echo -n "検索パターン（正規表現可）: "
        read -r PATTERN
        
        log_info "アーカイブ内を検索中..."
        
        # ストリーミングで検索
        MATCHES=$(gsutil cp "$ARCHIVE_PATH" - | tar tzf - | grep -E "$PATTERN" | grep -v "/$")
        
        if [ -z "$MATCHES" ]; then
            log_warn "一致するファイルが見つかりませんでした"
            exit 0
        fi
        
        MATCH_COUNT=$(echo "$MATCHES" | wc -l)
        log_info "見つかったファイル数: $MATCH_COUNT"
        
        if [ "$MATCH_COUNT" -gt 20 ]; then
            echo "$MATCHES" | head -20
            echo "... (他 $((MATCH_COUNT - 20)) ファイル)"
            echo -n "すべて表示しますか？ (y/N): "
            read -r SHOW_ALL
            if [[ $SHOW_ALL =~ ^[Yy]$ ]]; then
                echo "$MATCHES" | less
            fi
        else
            echo "$MATCHES"
        fi
        
        echo -n "これらのファイルを復元しますか？ (y/N): "
        read -r RESTORE_FILES
        
        if [[ $RESTORE_FILES =~ ^[Yy]$ ]]; then
            log_info "アーカイブをダウンロード中..."
            gsutil cp "$ARCHIVE_PATH" .
            
            echo "$MATCHES" | while read -r FILE; do
                tar xzf "$ARCHIVE_NAME" "$FILE" 2>/dev/null || true
            done
            
            log_info "✓ ファイルの復元完了"
        fi
        ;;
        
    4)
        # プレビューモード
        log_step "アーカイブ内容をプレビュー"
        log_info "アーカイブ構造を取得中..."
        
        # ツリー形式で表示
        gsutil cp "$ARCHIVE_PATH" - | tar tzf - | awk '
        BEGIN { depth = 0 }
        {
            path = $0
            n = split(path, parts, "/")
            
            # ディレクトリの場合
            if (substr(path, length(path)) == "/") {
                n--
            }
            
            # インデント
            indent = ""
            for (i = 1; i < n; i++) {
                indent = indent "  "
            }
            
            # 最後の要素を表示
            if (n > 0) {
                print indent "├── " parts[n]
            }
            
            # 最初の20エントリのみ表示
            if (NR > 20) {
                print "... (表示を省略)"
                exit
            }
        }'
        ;;
esac

# 復元後のオプション
echo -e "\n${CYAN}復元後のオプション:${NC}"
echo "1) 別のGCSバケットに再アップロード"
echo "2) ローカルで圧縮（zip形式）"
echo "3) 終了"
echo -n "選択 (1-3) [3]: "
read -r POST_ACTION

case "${POST_ACTION:-3}" in
    1)
        echo -n "アップロード先のプロジェクトID: "
        read -r DEST_PROJECT
        echo -n "アップロード先のバケット名: "
        read -r DEST_BUCKET
        
        log_info "プロジェクトを切り替え中..."
        gcloud config set project "$DEST_PROJECT" --quiet
        
        # バケット確認
        if ! gsutil ls "gs://${DEST_BUCKET}" &>/dev/null; then
            echo -n "バケットを作成しますか？ (y/N): "
            read -r CREATE
            if [[ $CREATE =~ ^[Yy]$ ]]; then
                gsutil mb "gs://${DEST_BUCKET}"
            fi
        fi
        
        log_info "アップロード中..."
        find . -name "*.tar.gz" -prune -o -type f -print | while read -r FILE; do
            RELATIVE="${FILE#./}"
            gsutil -m cp "$FILE" "gs://${DEST_BUCKET}/${RELATIVE}"
        done
        log_info "✓ アップロード完了"
        ;;
        
    2)
        ZIP_NAME="restored_$(date +%Y%m%d_%H%M%S).zip"
        log_info "ZIP形式で圧縮中: $ZIP_NAME"
        find . -name "*.tar.gz" -prune -o -type f -print | zip -@ "$ZIP_NAME"
        log_info "✓ 圧縮完了: ${RESTORE_DIR}/${ZIP_NAME}"
        ;;
esac

echo -e "\n${GREEN}処理が完了しました！${NC}"
echo "復元先: ${RESTORE_DIR}"