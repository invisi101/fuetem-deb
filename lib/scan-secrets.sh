#!/usr/bin/env bash
# scan-secrets.sh — Scan git repos for secrets using TruffleHog and Gitleaks
# Results are collated into a timestamped log in ~/dev/logs/

set -uo pipefail

TRUFFLEHOG="$(command -v trufflehog 2>/dev/null || true)"
GITLEAKS="$(command -v gitleaks 2>/dev/null || true)"

if [[ -z "$TRUFFLEHOG" && -z "$GITLEAKS" ]]; then
    echo "❌ Neither trufflehog nor gitleaks found in PATH. Install at least one."
    exit 1
fi
[[ -z "$TRUFFLEHOG" ]] && echo "⚠️  trufflehog not found — skipping TruffleHog scans."
[[ -z "$GITLEAKS" ]] && echo "⚠️  gitleaks not found — skipping Gitleaks scans."

LOG_DIR="${FUETEM_LOG_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fuetem/logs}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/secret-scan-${TIMESTAMP}.txt"

mkdir -p "$LOG_DIR"

# --- Discover repos ---
declare -a REPOS=()

# Find all git repos under ~/
while IFS= read -r gitdir; do
    REPOS+=("$(dirname "$gitdir")")
done < <(find "$HOME" -name .git -type d \
    -not -path "*/.cache/*" \
    -not -path "*/.local/share/nvim/*" \
    -not -path "*/.cargo/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/.local/share/omarchy/themes/*" \
    2>/dev/null)

if [ ${#REPOS[@]} -eq 0 ]; then
    echo "No git repos found. Exiting."
    exit 1
fi

# Sort repos for consistent output
IFS=$'\n' REPOS=($(sort <<<"${REPOS[*]}")); unset IFS

# --- Tool versions ---
TRUFFLEHOG_VERSION=""
GITLEAKS_VERSION=""
[[ -n "$TRUFFLEHOG" ]] && TRUFFLEHOG_VERSION=$("$TRUFFLEHOG" --version 2>&1 | head -1)
[[ -n "$GITLEAKS" ]] && GITLEAKS_VERSION=$("$GITLEAKS" version 2>&1 | head -1)

# --- Write log header ---
{
    echo "========================================"
    echo "  Secret Scan Report"
    echo "  ${TIMESTAMP}"
    echo "========================================"
    echo ""
    echo "Tools:"
    [[ -n "$TRUFFLEHOG" ]] && echo "  TruffleHog: ${TRUFFLEHOG_VERSION}"
    [[ -n "$GITLEAKS" ]] && echo "  Gitleaks:   ${GITLEAKS_VERSION}"
    echo ""
    echo "Repos scanned (${#REPOS[@]}):"
    for repo in "${REPOS[@]}"; do
        echo "  - $repo"
    done
    echo ""
    echo "========================================"
} > "$LOG_FILE"

# --- Tracking arrays (indexed, parallel with REPOS) ---
declare -a REPO_NAMES=()
declare -a TH_VERIFIED_ARR=()
declare -a TH_UNVERIFIED_ARR=()
declare -a GL_FINDINGS_ARR=()
TOTAL_TH_VERIFIED=0
TOTAL_TH_UNVERIFIED=0
TOTAL_GL=0

for i in "${!REPOS[@]}"; do
    repo="${REPOS[$i]}"
    repo_name=$(basename "$repo")
    # For nested repos, use parent/child as name
    parent=$(basename "$(dirname "$repo")")
    if [ "$parent" != "GITS" ] && [ "$parent" != "share" ]; then
        repo_name="${parent}/${repo_name}"
    fi
    REPO_NAMES+=("$repo_name")

    echo "Scanning: $repo_name ..."

    {
        echo ""
        echo "----------------------------------------"
        echo "  REPO: $repo"
        echo "----------------------------------------"
    } >> "$LOG_FILE"

    # --- TruffleHog ---
    th_verified=0
    th_unverified=0
    if [[ -n "$TRUFFLEHOG" ]]; then
        echo "  [TruffleHog] running..."
        th_output=$("$TRUFFLEHOG" git "file://$repo" --no-update 2>&1) || true

        if [ -n "$th_output" ]; then
            # TruffleHog prints a JSON summary line with "verified_secrets": N, "unverified_secrets": N
            th_verified=$(echo "$th_output" | { grep -oP '"verified_secrets":\s*\K\d+' || true; } | tail -1)
            th_unverified=$(echo "$th_output" | { grep -oP '"unverified_secrets":\s*\K\d+' || true; } | tail -1)
            [ -z "$th_verified" ] && th_verified=0
            [ -z "$th_unverified" ] && th_unverified=0
        fi

        {
            echo ""
            echo "  [TruffleHog]"
            echo "  Verified secrets:   $th_verified"
            echo "  Unverified secrets: $th_unverified"
            if [ -n "$th_output" ]; then
                echo ""
                echo "$th_output"
            else
                echo "  (no findings)"
            fi
        } >> "$LOG_FILE"
    fi

    TH_VERIFIED_ARR+=("$th_verified")
    TH_UNVERIFIED_ARR+=("$th_unverified")
    TOTAL_TH_VERIFIED=$((TOTAL_TH_VERIFIED + th_verified))
    TOTAL_TH_UNVERIFIED=$((TOTAL_TH_UNVERIFIED + th_unverified))

    # --- Gitleaks ---
    gl_leaks=0
    if [[ -n "$GITLEAKS" ]]; then
        echo "  [Gitleaks] running..."
        gl_output=$("$GITLEAKS" detect --source "$repo" --no-banner 2>&1) || true

        if [ -n "$gl_output" ]; then
            # Strip ANSI color codes, then match "leaks found: N" format
            gl_leaks=$(echo "$gl_output" | sed 's/\x1b\[[0-9;]*m//g' | { grep -oP 'leaks found:\s*\K\d+' || true; } | head -1)
            [ -z "$gl_leaks" ] && gl_leaks=0
        fi

        {
            echo ""
            echo "  [Gitleaks]"
            echo "  Leaks found: $gl_leaks"
            if [ -n "$gl_output" ]; then
                echo ""
                echo "$gl_output"
            else
                echo "  (no findings)"
            fi
        } >> "$LOG_FILE"
    fi

    GL_FINDINGS_ARR+=("$gl_leaks")
    TOTAL_GL=$((TOTAL_GL + gl_leaks))
done

# --- Summary ---
{
    echo ""
    echo "========================================"
    echo "  SUMMARY"
    echo "========================================"
    echo ""
    printf "  %-30s %12s %14s %10s\n" "Repository" "TH Verified" "TH Unverified" "GL Leaks"
    printf "  %-30s %12s %14s %10s\n" "------------------------------" "------------" "--------------" "----------"
    for i in "${!REPO_NAMES[@]}"; do
        printf "  %-30s %12d %14d %10d\n" \
            "${REPO_NAMES[$i]}" \
            "${TH_VERIFIED_ARR[$i]}" \
            "${TH_UNVERIFIED_ARR[$i]}" \
            "${GL_FINDINGS_ARR[$i]}"
    done
    printf "  %-30s %12s %14s %10s\n" "------------------------------" "------------" "--------------" "----------"
    printf "  %-30s %12d %14d %10d\n" "TOTAL" "$TOTAL_TH_VERIFIED" "$TOTAL_TH_UNVERIFIED" "$TOTAL_GL"
    echo ""
    echo "Log file: $LOG_FILE"
    echo "========================================"
} | tee -a "$LOG_FILE"

echo ""
echo "✅ Secret scan completed successfully."
echo "📄 Log file: $LOG_FILE"
