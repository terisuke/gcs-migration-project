#!/bin/bash

# ===============================================
# 完全なバケットダウンロードスクリプト - 100%成功を保証
# ===============================================

# 共通関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# エラーハンドリング設定
setup_error_handling

# 必須環境変数
REQUIRED_VARS=(
    "GCS_SOURCE_ACCOUNT"
    "GCS_SOURCE_PROJECT"
    "GCS_LOCAL_BACKUP_DIR"
)

# 設定
MAX_RETRIES=5
RETRY_DELAY=10

# メイン処理
main() {
    # 環境変数読み込み
    load_env || exit 1
    
    # 環境変数チェック
    check_required_env "${REQUIRED_VARS[@]}" || exit 1
    
    # 初期設定
    local timestamp=$(get_timestamp)
    local work_dir="${GCS_LOCAL_BACKUP_DIR}/${GCS_SOURCE_PROJECT}_backup_${timestamp}"
    
    # ディレクトリ作成
    create_directory "$work_dir" || exit 1
    cd "$work_dir"
    
    # ファイル初期化
    local status_file="${work_dir}/download_status.txt"
    local failed_file="${work_dir}/failed_buckets.txt"
    local log_file="${work_dir}/download.log"
    
    > "$status_file"
    > "$failed_file"
    > "$log_file"
    
    # 認証チェック
    log_step "認証確認"
    if ! check_auth "$GCS_SOURCE_ACCOUNT"; then
        log_info "ソースアカウントに切り替え中..."
        gcloud auth login "$GCS_SOURCE_ACCOUNT" || exit 1
    fi
    
    # プロジェクト設定
    set_project "$GCS_SOURCE_PROJECT" || exit 1
    
    # バケットリスト取得
    log_step "バケットリストを取得中"
    local buckets=$(run_gsutil ls -p "$GCS_SOURCE_PROJECT" 2>/dev/null || echo "")
    
    if [ -z "$buckets" ]; then
        log_error "バケットが見つかりませんでした"
        exit 1
    fi
    
    # バケット配列作成
    mapfile -t bucket_array <<< "$buckets"
    local total_buckets=${#bucket_array[@]}
    
    log_info "見つかったバケット数: ${total_buckets}"
    
    # ダウンロード実行
    log_step "ダウンロード開始"
    local success_count=0
    local failed_count=0
    local skipped_count=0
    
    for i in "${!bucket_array[@]}"; do
        local bucket_url="${bucket_array[$i]}"
        local bucket_name=$(basename "${bucket_url%/}")
        
        echo -e "\n${BLUE}=== バケット $((i+1))/${total_buckets}: ${bucket_name} ===${NC}"
        
        if download_bucket "$bucket_url" "$work_dir" "$status_file" "$failed_file" "$log_file"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
        
        show_progress $((i+1)) $total_buckets
    done
    
    echo # 改行
    
    # 結果集計
    analyze_results "$work_dir" "$status_file" "$failed_file"
}

# バケットが空かチェック
check_bucket_empty() {
    local bucket_url="$1"
    
    local object_count=$(run_gsutil ls "${bucket_url}**" 2>/dev/null | head -1 | wc -l)
    
    [ "$object_count" -eq 0 ]
}

# バケットダウンロード関数
download_bucket() {
    local bucket_url="$1"
    local work_dir="$2"
    local status_file="$3"
    local failed_file="$4"
    local log_file="$5"
    
    local bucket_name=$(basename "${bucket_url%/}")
    local bucket_dir="${work_dir}/${bucket_name}"
    
    # 空のバケットチェック
    log_info "[${bucket_name}] バケットの内容を確認中..."
    if check_bucket_empty "$bucket_url"; then
        log_warn "[${bucket_name}] 空のバケットです。スキップします"
        echo "SKIPPED_EMPTY: ${bucket_name}" >> "$status_file"
        create_directory "$bucket_dir"
        touch "$bucket_dir/.empty"
        return 0
    fi
    
    # リトライ付きダウンロード
    for attempt in $(seq 1 $MAX_RETRIES); do
        log_info "[${bucket_name}] ダウンロード試行 ${attempt}/${MAX_RETRIES}"
        
        create_directory "$bucket_dir"
        
        if run_gsutil -m cp -r "${bucket_url}**" "$bucket_dir/" 2>&1 | tee -a "$log_file"; then
            log_info "[${bucket_name}] ダウンロード成功"
            echo "SUCCESS: ${bucket_name}" >> "$status_file"
            return 0
        else
            log_warn "[${bucket_name}] ダウンロード失敗 (試行 ${attempt}/${MAX_RETRIES})"
            if [ $attempt -lt $MAX_RETRIES ]; then
                log_info "[${bucket_name}] ${RETRY_DELAY}秒後にリトライします..."
                sleep $RETRY_DELAY
                rm -rf "$bucket_dir"
            fi
        fi
    done
    
    log_error "[${bucket_name}] すべての試行が失敗しました"
    echo "FAILED: ${bucket_name}" >> "$status_file"
    echo "${bucket_url}" >> "$failed_file"
    return 1
}

# 結果分析関数
analyze_results() {
    local work_dir="$1"
    local status_file="$2"
    local failed_file="$3"
    
    local skipped_count=$(grep -c "SKIPPED_EMPTY:" "$status_file" || echo "0")
    local success_count=$(grep -c "SUCCESS:" "$status_file" || echo "0")
    local failed_count=$(grep -c "FAILED:" "$status_file" || echo "0")
    local total_count=$((success_count + skipped_count + failed_count))
    
    echo -e "\n${BLUE}=== ダウンロード完了 ===${NC}"
    echo -e "${GREEN}成功: ${success_count}/${total_count}${NC}"
    echo -e "${YELLOW}空のバケット（スキップ）: ${skipped_count}/${total_count}${NC}"
    echo -e "${RED}失敗: ${failed_count}/${total_count}${NC}"
    
    # 失敗したバケットの再試行
    if [ $failed_count -gt 0 ]; then
        handle_failed_buckets "$work_dir" "$status_file" "$failed_file"
    fi
    
    # 最終確認
    local final_failed=$(grep -c "FAILED:" "$status_file" || echo "0")
    local processed_count=$((success_count + skipped_count))
    
    if [ $final_failed -eq 0 ]; then
        log_info "すべてのバケットの処理が完了しました！"
        echo "$work_dir" > "${GCS_LOCAL_BACKUP_DIR}/latest_backup_path.txt"
        
        # サイズ確認
        log_info "ダウンロードしたデータのサイズ: $(get_human_readable_size "$work_dir")"
        
        # サマリー作成
        create_summary "$work_dir" "$status_file" $total_count $success_count $skipped_count $final_failed
        
        echo -e "${GREEN}✅ 100% 成功！すべてのバケットが処理されました。${NC}"
        echo -e "${GREEN}バックアップ場所: ${work_dir}${NC}"
    else
        log_error "完全なダウンロードに失敗しました。${final_failed}個のバケットがダウンロードできませんでした。"
        exit 1
    fi
}

# 失敗したバケットの処理
handle_failed_buckets() {
    local work_dir="$1"
    local status_file="$2"
    local failed_file="$3"
    
    log_warn "失敗したバケットの最終リトライを実行します..."
    
    while IFS= read -r bucket_url; do
        local bucket_name=$(basename "${bucket_url%/}")
        echo -e "\n${YELLOW}=== 最終リトライ: ${bucket_name} ===${NC}"
        
        # FAILEDステータスを一時的に削除
        sed -i.bak "/FAILED: ${bucket_name}/d" "$status_file"
        
        if download_bucket "$bucket_url" "$work_dir" "$status_file" "/dev/null" "/dev/null"; then
            log_info "[${bucket_name}] 最終リトライ成功"
        else
            echo "FAILED: ${bucket_name}" >> "$status_file"
        fi
    done < "$failed_file"
}

# サマリー作成
create_summary() {
    local work_dir="$1"
    local status_file="$2"
    local total="$3"
    local success="$4"
    local skipped="$5"
    local failed="$6"
    
    {
        echo "=== ダウンロードサマリー ==="
        echo "実行日時: $(date)"
        echo "総バケット数: ${total}"
        echo "成功: ${success}"
        echo "空のバケット: ${skipped}"
        echo "失敗: ${failed}"
        echo ""
        echo "=== 詳細 ==="
        cat "$status_file"
    } > "${work_dir}/download_summary.txt"
}

# メイン処理実行
main "$@"