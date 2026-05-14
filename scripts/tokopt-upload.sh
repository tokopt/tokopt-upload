#!/usr/bin/env bash
set -euo pipefail

VERSION="1.2.0"
DEFAULT_SERVER="https://tokopt.online"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' RESET=''
fi

# Defaults
SERVER="$DEFAULT_SERVER"
PROJECT_NAME=""
GUEST_TOKEN=""
DRY_RUN=false
NO_SUBAGENTS=false

usage() {
    cat <<EOF
${BOLD}tokopt-upload${RESET} v${VERSION} - Upload Claude Code logs for cost analysis

${BOLD}Usage:${RESET}
  $(basename "$0") [options]

${BOLD}Options:${RESET}
  --server URL         TokOpt server URL (default: ${DEFAULT_SERVER})
  --project NAME       Project name for this upload
  --token TOKEN        Reuse existing guest token
  --no-subagents       Exclude subagent sessions
  --dry-run            Show sessions without uploading
  -h, --help           Show this help
  -v, --version        Show version

${BOLD}Examples:${RESET}
  $(basename "$0")                          # Upload all sessions
  $(basename "$0") --dry-run                # Preview what would be uploaded
  $(basename "$0") --token abc-123          # Add to existing project
  $(basename "$0") --no-subagents           # Skip subagent conversations
  curl -fsSL https://tokopt.online/scripts/tokopt-upload.sh | bash

Discovers all Claude Code session files in ~/.claude/projects/ and uploads
them for analysis. No account needed - a guest project is created automatically.

${DIM}Data stays local until you run this script. Nothing is sent without your action.${RESET}
EOF
    exit 0
}

log()  { printf "${DIM}[%s]${RESET} %s\n" "$(date +%H:%M:%S)" "$*"; }
info() { printf "${BLUE}[%s]${RESET} %s\n" "$(date +%H:%M:%S)" "$*"; }
ok()   { printf "${GREEN}[%s]${RESET} %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "${YELLOW}[%s]${RESET} %s\n" "$(date +%H:%M:%S)" "$*"; }
err()  { printf "${RED}[%s]${RESET} %s\n" "$(date +%H:%M:%S)" "$*" >&2; }

die() {
    err "$@"
    exit 1
}

# ── Dependencies ──────────────────────────────────────────────────────────────

check_deps() {
    command -v curl >/dev/null 2>&1 || die "curl is required (https://curl.se)"
    command -v python3 >/dev/null 2>&1 || die "python3 is required for JSON parsing"
}

json_extract() {
    echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print($2)" 2>/dev/null
}

# ── Session Discovery ─────────────────────────────────────────────────────────

discover_sessions() {
    local claude_dir="${HOME}/.claude"
    local projects_dir="${claude_dir}/projects"

    [ -d "$projects_dir" ] || die "No Claude Code data found at ${projects_dir}"

    SESSION_FILES=()

    # Find main session files
    while IFS= read -r -d '' f; do
        SESSION_FILES+=("$f")
    done < <(find "$projects_dir" -name "*.jsonl" -not -path "*/subagents/*" -type f -print0 2>/dev/null)

    # Find subagent sessions unless excluded
    if [ "$NO_SUBAGENTS" = false ]; then
        while IFS= read -r -d '' f; do
            SESSION_FILES+=("$f")
        done < <(find "$projects_dir" -path "*/subagents/*.jsonl" -type f -print0 2>/dev/null)
    fi

    [ ${#SESSION_FILES[@]} -gt 0 ] || die "No session files found in ${projects_dir}"
}

count_user_messages() {
    grep -c '"type":"user"' "$1" 2>/dev/null || true
}

format_size() {
    local bytes="${1:-0}"
    python3 -c "
b = ${bytes}
if b >= 1048576: print(f'{b/1048576:.1f}MB')
elif b >= 1024: print(f'{b/1024:.0f}KB')
else: print(f'{b}B')
" 2>/dev/null
}

print_discovery() {
    local total_size=0
    local total_msgs=0
    local count=${#SESSION_FILES[@]}

    printf "\n${BOLD}Discovered %d session files:${RESET}\n\n" "$count"
    printf "  ${DIM}%-8s %-8s %-20s %s${RESET}\n" "Size" "Msgs" "Modified" "Path"
    printf "  ${DIM}%-8s %-8s %-20s %s${RESET}\n" "----" "----" "--------" "----"

    for f in "${SESSION_FILES[@]}"; do
        local size
        size=$(stat -c %s "$f" 2>/dev/null || echo 0)
        local msgs
        msgs=$(count_user_messages "$f")
        local modified
        modified=$(stat -c %y "$f" 2>/dev/null | cut -d. -f1 || echo "unknown")
        local short_path
        short_path=$(echo "$f" | sed "s|${HOME}/.claude/projects/||")

        printf "  %-8s %-8s %-20s " "$(format_size "$size")" "$msgs" "$modified"
        printf "${DIM}%s${RESET}\n" "$short_path"

        total_size=$((total_size + size))
        total_msgs=$((total_msgs + msgs))
    done

    printf "\n  ${BOLD}Total:${RESET} %d files, %s, %d user messages\n\n" \
        "$count" "$(format_size "$total_size")" "$total_msgs"
}

# ── Upload ────────────────────────────────────────────────────────────────────

BATCH_CHUNK_SIZE=20
BATCH_MODE=""

upload_session() {
    local file_path="$1"
    local token="${2:-}"
    local name="${3:-}"

    local args=(
        -sS
        -X POST
        "${SERVER}/api/v1/guest/upload/"
        -F "file=@${file_path}"
        -F "format=claude_code_jsonl"
    )

    [ -n "$token" ] && args+=(-F "guest_token=${token}")
    [ -n "$name" ] && args+=(-F "name=${name}")

    curl "${args[@]}"
}

upload_batch() {
    local -a file_paths=("$@")
    local token="${GUEST_TOKEN:-}"
    local name="${PROJECT_NAME:-Claude Code Analysis}"

    local args=(
        -sS
        -X POST
        "${SERVER}/api/v1/guest/upload/batch/"
        -F "format=claude_code_jsonl"
    )

    for f in "${file_paths[@]}"; do
        args+=(-F "files=@${f}")
    done

    [ -n "$token" ] && args+=(-F "guest_token=${token}")
    [ -n "$name" ] && args+=(-F "name=${name}")

    curl "${args[@]}"
}

detect_batch_mode() {
    local response
    response=$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
        "${SERVER}/api/v1/guest/upload/batch/" 2>/dev/null) || true
    if [ "$response" = "400" ] || [ "$response" = "405" ] || [ "$response" = "415" ]; then
        BATCH_MODE="batch"
        log "Using batch upload mode (server supports /upload/batch/)"
    else
        BATCH_MODE="single"
        log "Using single-file upload mode (batch endpoint not available)"
    fi
}

upload_history() {
    local history_file="${HOME}/.claude/history.jsonl"
    local token="$1"

    [ -f "$history_file" ] || return 0

    local size
    size=$(stat -c %s "$history_file" 2>/dev/null || echo 0)
    [ "$size" -gt 0 ] || return 0

    log "Uploading command history ($(format_size "$size"))..."
    curl -sS -X POST "${SERVER}/api/v1/guest/upload/" \
        -F "file=@${history_file}" \
        -F "format=claude_code_jsonl" \
        -F "guest_token=${token}" \
        -F "name=history-metadata" 2>&1 || true
}

do_uploads() {
    local total=${#SESSION_FILES[@]}

    # Detect batch mode support
    detect_batch_mode

    if [ "$BATCH_MODE" = "batch" ]; then
        do_batch_uploads "$total"
    else
        do_single_uploads "$total"
    fi
}

do_single_uploads() {
    local total="$1"
    local token="${GUEST_TOKEN:-}"
    local name="${PROJECT_NAME:-Claude Code Analysis}"
    local current=0
    local failed=0

    printf "${BOLD}Uploading %d sessions to %s (single-file mode)${RESET}\n\n" "$total" "$SERVER"

    for f in "${SESSION_FILES[@]}"; do
        current=$((current + 1))
        local size
        size=$(stat -c %s "$f" 2>/dev/null || echo 0)

        printf "  [${DIM}%d/%d${RESET}] Uploading %s (%s)..." "$current" "$total" \
            "$(basename "$f")" "$(format_size "$size")"

        local response
        response=$(upload_session "$f" "$token" "$name" 2>&1) || {
            printf " ${RED}FAILED${RESET}\n"
            warn "Upload failed: $(echo "$response" | head -1)"
            failed=$((failed + 1))
            continue
        }

        if [ -z "$token" ]; then
            token=$(json_extract "$response" "d.get('guest_token','')")
            [ -n "$token" ] && GUEST_TOKEN="$token"
        fi

        printf " ${GREEN}ok${RESET}\n"
    done

    printf "\n"

    if [ -n "${GUEST_TOKEN:-}" ]; then
        upload_history "$GUEST_TOKEN"
    fi

    if [ "$failed" -gt 0 ]; then
        warn "%d uploads failed" "$failed"
    fi

    ok "%d/%d sessions uploaded successfully" "$((total - failed))" "$total"
    [ -n "${GUEST_TOKEN:-}" ] || die "Failed to create guest project - no token received"
}

do_batch_uploads() {
    local total="$1"
    local chunks=$(( (total + BATCH_CHUNK_SIZE - 1) / BATCH_CHUNK_SIZE ))
    local current=0
    local failed=0
    local uploaded=0

    printf "${BOLD}Uploading %d sessions to %s (batch mode, %d files per batch)${RESET}\n\n" \
        "$total" "$SERVER" "$BATCH_CHUNK_SIZE"

    for (( i=0; i < total; i += BATCH_CHUNK_SIZE )); do
        current=$((current + 1))
        local end=$((i + BATCH_CHUNK_SIZE))
        [ "$end" -gt "$total" ] && end=$total
        local chunk_size=$((end - i))

        # Build chunk array
        local chunk=()
        for (( j=i; j < end; j++ )); do
            chunk+=("${SESSION_FILES[$j]}")
        done

        printf "  [${DIM}%d/%d${RESET}] Uploading batch (%d files)..." "$current" "$chunks" "$chunk_size"

        local response
        response=$(upload_batch "${chunk[@]}" 2>&1) || {
            printf " ${RED}FAILED${RESET}\n"
            warn "Batch upload failed, retrying files individually..."

            # Fallback to single-file for this chunk
            for f in "${chunk[@]}"; do
                response=$(upload_session "$f" "${GUEST_TOKEN:-}" "${PROJECT_NAME:-Claude Code Analysis}" 2>&1) || {
                    failed=$((failed + 1))
                    continue
                }
                if [ -z "${GUEST_TOKEN:-}" ]; then
                    local token
                    token=$(json_extract "$response" "d.get('guest_token','')")
                    [ -n "$token" ] && GUEST_TOKEN="$token"
                fi
                uploaded=$((uploaded + 1))
            done
            continue
        }

        # Extract guest_token from response
        if [ -z "${GUEST_TOKEN:-}" ]; then
            local token
            token=$(json_extract "$response" "d.get('guest_token','')")
            [ -n "$token" ] && GUEST_TOKEN="$token"
        fi

        uploaded=$((uploaded + chunk_size))
        printf " ${GREEN}ok${RESET}\n"
    done

    printf "\n"

    if [ -n "${GUEST_TOKEN:-}" ]; then
        upload_history "$GUEST_TOKEN"
    fi

    if [ "$failed" -gt 0 ]; then
        warn "%d uploads failed" "$failed"
    fi

    ok "%d/%d sessions uploaded successfully" "$uploaded" "$total"
    [ -n "${GUEST_TOKEN:-}" ] || die "Failed to create guest project - no token received"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --server)    SERVER="$2"; shift 2 ;;
            --project)   PROJECT_NAME="$2"; shift 2 ;;
            --token)     GUEST_TOKEN="$2"; shift 2 ;;
            --no-subagents) NO_SUBAGENTS=true; shift ;;
            --dry-run)   DRY_RUN=true; shift ;;
            -h|--help)   usage ;;
            -v|--version) echo "tokopt-upload v${VERSION}"; exit 0 ;;
            *) die "Unknown option: $1. Use --help for usage." ;;
        esac
    done

    printf "\n${BOLD}tokopt-upload${RESET} v${VERSION} - Claude Code cost analysis\n"
    printf "${DIM}Server: %s${RESET}\n\n" "$SERVER"

    check_deps
    discover_sessions
    print_discovery

    if [ "$DRY_RUN" = true ]; then
        printf "${YELLOW}Dry run - no files uploaded.${RESET}\n"
        printf "Run without --dry-run to upload and analyze.\n"
        exit 0
    fi

    do_uploads

    printf "\n${BOLD}%d sessions uploaded.${RESET}\n" "${#SESSION_FILES[@]}"
    printf "  ${DIM}Analysis runs in the background — refresh the dashboard to see results.${RESET}\n"
    printf "  ${GREEN}Dashboard:${RESET}   %s/results/%s/\n" "$SERVER" "$GUEST_TOKEN"
    printf "  ${GREEN}Flow Graph:${RESET}  %s/results/%s/flow\n" "$SERVER" "$GUEST_TOKEN"
    printf "\n"
}

main "$@"
