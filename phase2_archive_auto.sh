#!/bin/bash

# ===============================================
# フェーズ2: ローカルでアーカイブ作成 (自動化版)
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
    
    # ヘッダー表示（clearを使用しない）
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}          フェーズ2: ローカルでアーカイブ作成${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # latest_backup_path.txtから自動的にディレクトリを取得
    local work_dir
    if [ -f "${GCS_LOCAL_BACKUP_DIR}/latest_backup_path.txt" ]; then
        work_dir=$(cat "${GCS_LOCAL_BACKUP_DIR}/latest_backup_path.txt")
        log_info "最新のバックアップパスを使用: ${work_dir}"
    else
        log_error "latest_backup_path.txtが見つかりません。phase1を先に実行してください。"
        exit 1
    fi
    
    # ディレクトリ存在確認
    if [ ! -d "$work_dir" ]; then
        log_error "指定されたディレクトリが存在しません: ${work_dir}"
        exit 1
    fi
    
    # アーカイブ名を自動生成
    local backup_name=$(basename "$work_dir")
    local archive_name="${backup_name}.tar.gz"
    local parent_dir=$(dirname "$work_dir")
    local archive_path="${parent_dir}/${archive_name}"
    
    # 既存ファイルがある場合は上書き
    if [ -f "$archive_path" ]; then
        log_warn "既存のアーカイブを上書きします: ${archive_name}"
    fi
    
    # 圧縮レベルを環境変数から取得（デフォルト: 6）
    local compression_level="${DEFAULT_COMPRESSION_LEVEL}"
    
    # アーカイブ作成
    create_archive "$work_dir" "$archive_name" "$compression_level"
    
    # メタデータ作成
    create_metadata "$work_dir" "$archive_name"
    
    # 完了メッセージ
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ フェーズ2完了！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_info "アーカイブファイル: ${archive_path}"
    log_info "次はフェーズ3でアップロードを実行してください"
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
    log_info "アーカイブ名: ${archive_name}"
    log_info "圧縮レベル: ${compression_level}"
    log_info "これには時間がかかる場合があります..."
    
    cd "$parent_dir"
    
    # tar実行（macOS互換）
    # macOSのBSD tarは--gzip-compression-levelをサポートしないため、環境変数で設定
    export GZIP="-${compression_level}"
    if tar czf "$archive_name" "$backup_name"; then
        local archive_size=$(get_human_readable_size "$archive_path")
        log_info "✓ アーカイブ作成成功"
        log_info "アーカイブサイズ: ${archive_size}"
        
        # 圧縮率計算
        if command -v bc >/dev/null 2>&1; then
            local original_bytes=$(du -sk "$work_dir" | awk '{print $1*1024}')
            local archive_bytes=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)
            
            if [ -n "$archive_bytes" ] && [ "$original_bytes" -gt 0 ]; then
                local ratio=$(echo "scale=2; 100 - ($archive_bytes * 100 / $original_bytes)" | bc)
                log_info "圧縮率: ${ratio}%"
            fi
        fi
    else
        log_error "アーカイブの作成に失敗しました"
        exit 1
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

# メイン処理実行
main "$@"