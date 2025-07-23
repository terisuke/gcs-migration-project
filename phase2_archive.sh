#!/bin/bash

# ===============================================
# フェーズ2: ローカルでアーカイブ作成
# 認証不要 - ローカルファイル操作のみ
# ===============================================

# 共通関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# エラーハンドリング設定
setup_error_handling

# 必須環境変数
REQUIRED_VARS=(
    "GCS_LOCAL_BACKUP_DIR"
    "GCS_SOURCE_PROJECT"
)

# デフォルト設定
DEFAULT_COMPRESSION_LEVEL="${GCS_DEFAULT_COMPRESSION_LEVEL:-6}"

# メイン処理
main() {
    # 環境変数読み込み
    load_env || exit 1
    
    # 環境変数チェック
    check_required_env "${REQUIRED_VARS[@]}" || exit 1
    
    # ヘッダー表示
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}          フェーズ2: ローカルでアーカイブ作成${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # ダウンロードディレクトリの選択
    local work_dir=$(select_work_directory)
    
    # アーカイブ設定
    local archive_name
    local compression_level
    
    archive_name=$(get_archive_name "$work_dir")
    compression_level=$(select_compression_level)
    
    # アーカイブ作成
    create_archive "$work_dir" "$archive_name" "$compression_level"
    
    # メタデータ作成
    create_metadata "$work_dir" "$archive_name"
    
    # 完了メッセージ
    show_completion_message "$archive_name"
}

# 作業ディレクトリ選択
select_work_directory() {
    log_step "フェーズ1でダウンロードしたディレクトリを指定"
    
    local work_dir
    
    # latest_backup_path.txtから自動検出
    if [ -f "${GCS_LOCAL_BACKUP_DIR}/latest_backup_path.txt" ]; then
        work_dir=$(cat "${GCS_LOCAL_BACKUP_DIR}/latest_backup_path.txt")
        log_info "最新のバックアップパスを自動検出しました: ${work_dir}"
        
        if confirm_action "このディレクトリを使用しますか？" "y"; then
            log_info "自動検出されたパスを使用します"
        else
            work_dir=$(prompt_for_directory)
        fi
    else
        work_dir=$(prompt_for_directory)
    fi
    
    # ディレクトリ存在確認
    if [ ! -d "$work_dir" ]; then
        log_error "指定されたディレクトリが存在しません: ${work_dir}"
        exit 1
    fi
    
    # ディレクトリ情報表示
    log_info "選択されたディレクトリ: ${work_dir}"
    log_info "ディレクトリサイズ: $(get_human_readable_size "$work_dir")"
    
    echo "$work_dir"
}

# ディレクトリ入力プロンプト
prompt_for_directory() {
    # 最新のバックアップを提案
    if [ -n "${GCS_LOCAL_BACKUP_DIR:-}" ] && [ -d "${GCS_LOCAL_BACKUP_DIR}" ]; then
        local latest_backup=$(ls -dt "${GCS_LOCAL_BACKUP_DIR}"/*_backup_* 2>/dev/null | head -1 || echo "")
        if [ -n "$latest_backup" ]; then
            echo "最新のバックアップ: $latest_backup"
        fi
    fi
    
    echo ""
    echo -n "ディレクトリパスを入力: "
    read -r work_dir
    echo "$work_dir"
}

# アーカイブ名取得
get_archive_name() {
    local work_dir="$1"
    local parent_dir=$(dirname "$work_dir")
    local backup_name=$(basename "$work_dir")
    
    # アーカイブ設定
    log_step "アーカイブ名を設定"
    local default_name="${backup_name}.tar.gz"
    echo "デフォルト: ${default_name}"
    echo -n "アーカイブ名を入力 [Enter でデフォルト]: "
    read -r custom_name
    
    local archive_name="${custom_name:-$default_name}"
    local archive_path="${parent_dir}/${archive_name}"
    
    # 既存ファイル確認
    if [ -f "$archive_path" ]; then
        log_warn "同名のアーカイブが既に存在します: ${archive_name}"
        if ! confirm_action "上書きしますか？" "n"; then
            log_info "処理を中止しました"
            exit 0
        fi
    fi
    
    echo "$archive_name"
}

# 圧縮レベル選択
select_compression_level() {
    log_step "圧縮オプションを選択"
    echo "1) 高速圧縮（圧縮率: 低、速度: 速い）"
    echo "2) 標準圧縮（圧縮率: 中、速度: 普通）※推奨"
    echo "3) 最大圧縮（圧縮率: 高、速度: 遅い）"
    echo -n "選択 (1-3) [2]: "
    read -r compress_option
    
    case "${compress_option:-2}" in
        1) echo 1 ;;
        3) echo 9 ;;
        *) echo "$DEFAULT_COMPRESSION_LEVEL" ;;
    esac
}

# アーカイブ作成
create_archive() {
    local work_dir="$1"
    local archive_name="$2"
    local compression_level="$3"
    
    local parent_dir=$(dirname "$work_dir")
    local backup_name=$(basename "$work_dir")
    local archive_path="${parent_dir}/${archive_name}"
    
    log_step "アーカイブを作成中"
    log_info "これには時間がかかる場合があります..."
    log_info "アーカイブ名: ${archive_name}"
    log_info "圧縮レベル: ${compression_level}"
    
    cd "$parent_dir"
    
    # プログレス表示付きでtar実行
    if command -v pv >/dev/null 2>&1; then
        # pvコマンドがある場合はプログレスバー表示
        tar cf - "$backup_name" | \
            pv -s $(du -sb "$backup_name" | awk '{print $1}') | \
            gzip -${compression_level} > "$archive_name"
    else
        # pvがない場合は進捗ドット表示
        tar czf "$archive_name" "$backup_name" \
            --checkpoint=1000 \
            --checkpoint-action=dot \
            --gzip-compression-level=${compression_level}
        echo ""
    fi
    
    # アーカイブ検証
    log_step "アーカイブを検証"
    if [ -f "$archive_path" ]; then
        local archive_size=$(get_human_readable_size "$archive_path")
        log_info "✓ アーカイブ作成成功"
        log_info "アーカイブサイズ: ${archive_size}"
        
        # 圧縮率計算
        calculate_compression_ratio "$work_dir" "$archive_path"
    else
        log_error "アーカイブの作成に失敗しました"
        exit 1
    fi
}

# 圧縮率計算
calculate_compression_ratio() {
    local work_dir="$1"
    local archive_path="$2"
    
    if command -v bc >/dev/null 2>&1; then
        local original_bytes=$(du -sb "$work_dir" | cut -f1)
        local archive_bytes=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)
        
        if [ -n "$archive_bytes" ] && [ "$original_bytes" -gt 0 ]; then
            local ratio=$(echo "scale=2; 100 - ($archive_bytes * 100 / $original_bytes)" | bc)
            log_info "圧縮率: ${ratio}%"
        fi
    fi
}

# メタデータ作成
create_metadata() {
    local work_dir="$1"
    local archive_name="$2"
    
    local parent_dir=$(dirname "$work_dir")
    local archive_path="${parent_dir}/${archive_name}"
    local metadata_file="${archive_path}.json"
    
    log_step "メタデータファイルを作成"
    
    # チェックサム計算
    local checksum=""
    if command -v sha256sum >/dev/null 2>&1; then
        checksum=$(sha256sum "$archive_path" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        checksum=$(shasum -a 256 "$archive_path" | cut -d' ' -f1)
    fi
    
    # メタデータ作成
    cat > "$metadata_file" << EOF
{
    "archive_name": "${archive_name}",
    "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "source_project": "${GCS_SOURCE_PROJECT}",
    "source_directory": "$(basename "$work_dir")",
    "archive_size": "$(get_human_readable_size "$archive_path")",
    "archive_bytes": $(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null || echo "0"),
    "checksum_sha256": "${checksum}",
    "compression_level": "${compression_level}",
    "bucket_count": $(find "$work_dir" -maxdepth 1 -type d ! -path "$work_dir" | wc -l)
}
EOF
    
    log_info "✓ メタデータファイル作成完了: ${metadata_file}"
}

# 完了メッセージ表示
show_completion_message() {
    local archive_name="$1"
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ フェーズ2完了！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_info "アーカイブファイル: ${archive_name}"
    echo ""
    echo "次のステップ:"
    echo "1. デスティネーションアカウントにログイン:"
    echo "   ${YELLOW}gcloud auth login ${GCS_DEST_ACCOUNT:-your-dest-account@domain.com}${NC}"
    echo ""
    echo "2. フェーズ3を実行:"
    echo "   ${YELLOW}./phase3_upload.sh${NC}"
}

# メイン処理実行
main "$@"