#!/bin/bash

# ===============================================
# フェーズ3: アーカイブをデスティネーションプロジェクトへアップロード
# ===============================================

# 共通関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# エラーハンドリング設定
setup_error_handling

# 必須環境変数
REQUIRED_VARS=(
    "GCS_DEST_ACCOUNT"
    "GCS_DEST_PROJECT"
    "GCS_ARCHIVE_BUCKET"
    "GCS_LOCAL_BACKUP_DIR"
)

# デフォルト設定
LARGE_FILE_THRESHOLD=$((150 * 1024 * 1024))  # 150MB
PARALLEL_THRESHOLD="${GCS_PARALLEL_UPLOAD_THRESHOLD:-150M}"
PARALLEL_COMPONENT_SIZE="${GCS_PARALLEL_UPLOAD_COMPONENT_SIZE:-50M}"
DEFAULT_REGION="${GCS_DEFAULT_REGION:-asia-northeast1}"

# メイン処理
main() {
    # 環境変数読み込み
    load_env || exit 1
    
    # 環境変数チェック
    check_required_env "${REQUIRED_VARS[@]}" || exit 1
    
    # ヘッダー表示
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}     フェーズ3: デスティネーションプロジェクトへアップロード${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 認証チェック
    log_step "認証確認"
    if ! check_auth "$GCS_DEST_ACCOUNT"; then
        log_info "デスティネーションアカウントに切り替え中..."
        gcloud auth login "$GCS_DEST_ACCOUNT" || exit 1
    fi
    
    # プロジェクト設定
    set_project "$GCS_DEST_PROJECT" || exit 1
    
    # アーカイブファイル選択
    local archive_path=$(select_archive_file)
    local archive_name=$(basename "$archive_path")
    
    # アップロード先設定
    local bucket_name=$(select_destination_bucket)
    local dest_bucket="gs://${bucket_name}/"
    
    # バケット確認・作成
    verify_or_create_bucket "$bucket_name"
    
    # アップロード実行
    local upload_result=$(upload_archive "$archive_path" "$dest_bucket")
    
    # メタデータアップロード
    upload_metadata "$archive_path" "$dest_bucket"
    
    # アクセス権限設定（オプション）
    configure_permissions "$dest_bucket" "$archive_name"
    
    # クリーンアップ（オプション）
    cleanup_local_files "$archive_path"
    
    # 完了メッセージ
    show_completion_message "$archive_path" "$dest_bucket" "$upload_result"
}

# アーカイブファイル選択
select_archive_file() {
    log_step "アップロードするアーカイブファイルを選択"
    
    # 最新のtar.gzファイルを検索
    local latest_archive=""
    if [ -d "$GCS_LOCAL_BACKUP_DIR" ]; then
        latest_archive=$(find "$GCS_LOCAL_BACKUP_DIR" -name "*.tar.gz" -type f -exec ls -t {} + 2>/dev/null | head -1)
    fi
    
    if [ -n "$latest_archive" ]; then
        echo "最新のアーカイブ: $latest_archive"
        echo "サイズ: $(get_human_readable_size "$latest_archive")"
    else
        echo "例: ${GCS_LOCAL_BACKUP_DIR}/yolov8environment_backup_20240115_123456.tar.gz"
    fi
    
    echo ""
    echo -n "アーカイブファイルのパスを入力: "
    read -r archive_path
    
    # ファイル存在確認
    if [ ! -f "$archive_path" ]; then
        log_error "指定されたファイルが存在しません: ${archive_path}"
        exit 1
    fi
    
    echo "$archive_path"
}

# デスティネーションバケット選択
select_destination_bucket() {
    log_step "アップロード先の設定"
    
    echo "デフォルトのバケット名: ${GCS_ARCHIVE_BUCKET}"
    
    if confirm_action "デフォルトのバケットを使用しますか？" "y"; then
        echo "$GCS_ARCHIVE_BUCKET"
    else
        echo -n "バケット名を入力: "
        read -r bucket_name
        echo "$bucket_name"
    fi
}

# バケット確認・作成
verify_or_create_bucket() {
    local bucket_name="$1"
    local bucket_url="gs://${bucket_name}"
    
    log_info "バケット ${bucket_url} を確認中..."
    
    if ! run_gsutil ls "$bucket_url" >/dev/null 2>&1; then
        log_warn "バケットが存在しません"
        
        if confirm_action "バケットを作成しますか？" "y"; then
            create_bucket "$bucket_name"
        else
            log_error "バケットが存在しません。処理を中止します"
            exit 1
        fi
    else
        log_info "✓ バケットが存在します"
    fi
}

# バケット作成
create_bucket() {
    local bucket_name="$1"
    
    log_info "バケットを作成中: ${bucket_name}"
    
    # リージョン選択
    local region=$(select_region)
    
    # バケット作成
    if run_gsutil mb -p "$GCS_DEST_PROJECT" -l "$region" "gs://${bucket_name}/"; then
        log_info "✓ バケット作成成功: ${bucket_name}"
    else
        log_error "バケット作成に失敗しました"
        exit 1
    fi
}

# リージョン選択
select_region() {
    echo "バケットのリージョンを選択:"
    echo "1) asia-northeast1 (東京)"
    echo "2) asia-northeast2 (大阪)"
    echo "3) us-central1 (アイオワ)"
    echo "4) multi-region asia"
    echo -n "選択 (1-4) [1]: "
    read -r region_choice
    
    case "${region_choice:-1}" in
        1) echo "asia-northeast1" ;;
        2) echo "asia-northeast2" ;;
        3) echo "us-central1" ;;
        4) echo "asia" ;;
        *) echo "$DEFAULT_REGION" ;;
    esac
}

# アーカイブアップロード
upload_archive() {
    local archive_path="$1"
    local dest_bucket="$2"
    
    local archive_name=$(basename "$archive_path")
    local archive_size=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null || echo "0")
    
    log_step "アーカイブをアップロード"
    log_info "ファイル: ${archive_name}"
    log_info "サイズ: $(get_human_readable_size "$archive_path")"
    log_info "アップロード先: ${dest_bucket}${archive_name}"
    
    # 並列アップロードの選択
    local use_parallel=true
    if [ "$archive_size" -gt "$LARGE_FILE_THRESHOLD" ]; then
        log_info "大きなファイルのため、並列アップロードを推奨します"
        use_parallel=$(confirm_action "並列アップロードを有効にしますか？" "y" && echo true || echo false)
    fi
    
    # アップロード実行
    local start_time=$(date +%s)
    
    if [ "$use_parallel" = true ]; then
        log_info "並列アップロードを実行中..."
        run_gsutil -o GSUtil:parallel_composite_upload_threshold=${PARALLEL_THRESHOLD} \
                   -o GSUtil:parallel_composite_upload_component_size=${PARALLEL_COMPONENT_SIZE} \
                   cp "$archive_path" "${dest_bucket}${archive_name}"
    else
        log_info "通常アップロードを実行中..."
        run_gsutil cp "$archive_path" "${dest_bucket}${archive_name}"
    fi
    
    local end_time=$(date +%s)
    local upload_time=$((end_time - start_time))
    
    if [ $? -eq 0 ]; then
        log_info "✓ アップロード成功！"
        verify_upload "${dest_bucket}${archive_name}" "$archive_size"
        echo "$upload_time"
    else
        log_error "アップロードに失敗しました"
        exit 1
    fi
}

# アップロード確認
verify_upload() {
    local gcs_path="$1"
    local expected_size="$2"
    
    log_info "アップロードを確認中..."
    
    local remote_size=$(run_gsutil du "$gcs_path" 2>/dev/null | awk '{print $1}')
    
    if [ -n "$remote_size" ]; then
        if [ "$remote_size" -eq "$expected_size" ]; then
            log_info "✓ ファイルサイズ検証: OK"
        else
            log_warn "⚠ ファイルサイズが一致しません"
            log_warn "  ローカル: ${expected_size} bytes"
            log_warn "  リモート: ${remote_size} bytes"
        fi
    fi
}

# メタデータアップロード
upload_metadata() {
    local archive_path="$1"
    local dest_bucket="$2"
    
    local metadata_file="${archive_path}.json"
    
    if [ -f "$metadata_file" ]; then
        log_step "メタデータファイルをアップロード"
        
        local metadata_name=$(basename "$metadata_file")
        if run_gsutil cp "$metadata_file" "${dest_bucket}${metadata_name}"; then
            log_info "✓ メタデータアップロード成功"
        else
            log_warn "メタデータのアップロードに失敗しました（続行します）"
        fi
    fi
}

# アクセス権限設定
configure_permissions() {
    local dest_bucket="$1"
    local archive_name="$2"
    
    echo ""
    echo -e "${YELLOW}オプション: アクセス権限の設定${NC}"
    echo "1) プロジェクト内のみアクセス可能（デフォルト）"
    echo "2) 特定のユーザー/グループに読み取り権限を付与"
    echo "3) スキップ"
    echo -n "選択 (1-3) [3]: "
    read -r permission_choice
    
    if [ "${permission_choice:-3}" = "2" ]; then
        echo -n "アクセスを許可するメールアドレス（カンマ区切り）: "
        read -r allowed_users
        
        IFS=',' read -ra users <<< "$allowed_users"
        for user in "${users[@]}"; do
            user=$(echo "$user" | xargs)  # trim whitespace
            log_info "権限を付与: ${user}"
            run_gsutil acl ch -u "${user}:R" "${dest_bucket}${archive_name}"
        done
    fi
}

# ローカルファイルクリーンアップ
cleanup_local_files() {
    local archive_path="$1"
    
    echo ""
    echo -e "${YELLOW}クリーンアップ${NC}"
    
    if confirm_action "ローカルのアーカイブファイルを削除しますか？" "n"; then
        log_info "ローカルファイルを削除中..."
        rm -f "$archive_path"
        rm -f "${archive_path}.json"
        log_info "✓ 削除完了"
    fi
}

# 完了メッセージ表示
show_completion_message() {
    local archive_path="$1"
    local dest_bucket="$2"
    local upload_time="${3:-0}"
    
    local archive_name=$(basename "$archive_path")
    local archive_size=$(get_human_readable_size "$archive_path")
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ すべての処理が完了しました！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "アップロード先:"
    echo "  ${BLUE}${dest_bucket}${archive_name}${NC}"
    
    if [ -f "${archive_path}.json" ]; then
        echo "  ${BLUE}${dest_bucket}$(basename "${archive_path}.json")${NC}"
    fi
    
    echo ""
    echo "アップロード統計:"
    echo "  ファイルサイズ: ${archive_size}"
    
    if [ "$upload_time" -gt 0 ]; then
        echo "  所要時間: $((upload_time / 60))分 $((upload_time % 60))秒"
        
        # 転送速度計算
        local size_bytes=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null || echo "0")
        if [ "$size_bytes" -gt 0 ] && command -v bc >/dev/null 2>&1; then
            local speed=$(echo "scale=2; $size_bytes / $upload_time / 1024 / 1024" | bc)
            echo "  転送速度: ${speed} MB/s"
        fi
    fi
    
    echo ""
    echo "リストア方法:"
    echo "1. アーカイブをダウンロード:"
    echo "   ${YELLOW}gsutil cp ${dest_bucket}${archive_name} .${NC}"
    echo ""
    echo "2. アーカイブを展開:"
    echo "   ${YELLOW}tar xzf ${archive_name}${NC}"
    echo ""
    echo "または、advanced_restore.sh を使用してインタラクティブにリストア可能です"
}

# メイン処理実行
main "$@"