#!/bin/bash

# ===============================================
# 共通関数ライブラリ
# ===============================================

# カラー定義
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

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

# 環境変数読み込み関数
load_env() {
    if [ -f .env ]; then
        set -a
        source .env
        set +a
        return 0
    else
        log_error ".env file not found. Run 'make setup' first."
        return 1
    fi
}

# 必須環境変数チェック関数
check_required_env() {
    local vars=("$@")
    local missing=()
    
    for var in "${vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing+=("$var")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Required environment variables are not set:"
        for var in "${missing[@]}"; do
            echo "  - $var"
        done
        return 1
    fi
    
    return 0
}

# 認証チェック関数
check_auth() {
    local expected_account="$1"
    local current_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)")
    
    if [[ "$current_account" != "$expected_account" ]]; then
        log_warn "Not logged in as $expected_account (current: $current_account)"
        log_info "Please run: gcloud auth login $expected_account"
        return 1
    fi
    
    return 0
}

# プロジェクト設定関数
set_project() {
    local project="$1"
    
    log_info "Setting project to: $project"
    if gcloud config set project "$project" >/dev/null 2>&1; then
        return 0
    else
        log_error "Failed to set project to: $project"
        return 1
    fi
}

# ディレクトリ作成関数（エラーハンドリング付き）
create_directory() {
    local dir="$1"
    
    if [ -d "$dir" ]; then
        return 0
    fi
    
    if mkdir -p "$dir"; then
        log_info "Created directory: $dir"
        return 0
    else
        log_error "Failed to create directory: $dir"
        return 1
    fi
}

# ファイルサイズ取得関数（人間が読める形式）
get_human_readable_size() {
    local path="$1"
    
    if [ -d "$path" ]; then
        du -sh "$path" 2>/dev/null | cut -f1
    elif [ -f "$path" ]; then
        ls -lh "$path" 2>/dev/null | awk '{print $5}'
    else
        echo "0"
    fi
}

# gsutil実行関数（macOS対応）
run_gsutil() {
    gsutil -o "GSUtil:parallel_process_count=1" "$@"
}

# 進捗バー表示関数
show_progress() {
    local current=$1
    local total=$2
    local width=50
    
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%$((width - filled))s" | tr ' ' '-'
    printf "] %d%% (%d/%d)" "$percent" "$current" "$total"
}

# タイムスタンプ生成関数
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# 確認プロンプト関数
confirm_action() {
    local message="${1:-Continue?}"
    local default="${2:-n}"
    
    if [[ "$default" =~ ^[Yy]$ ]]; then
        local prompt="$message [Y/n]: "
    else
        local prompt="$message [y/N]: "
    fi
    
    echo -n "$prompt"
    read -r response
    
    if [ -z "$response" ]; then
        response=$default
    fi
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# クリーンアップ関数（トラップ用）
cleanup_on_exit() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_warn "Script exited with error code: $exit_code"
    fi
    
    # 一時ファイルのクリーンアップなど
    return $exit_code
}

# エラーハンドラー設定
setup_error_handling() {
    set -euo pipefail
    trap cleanup_on_exit EXIT
}