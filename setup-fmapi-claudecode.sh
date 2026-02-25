#!/bin/bash
set -euo pipefail
umask 077

# Temp file cleanup on exit/interrupt
declare -a _CLEANUP_FILES=()
_cleanup() {
  for f in "${_CLEANUP_FILES[@]+"${_CLEANUP_FILES[@]}"}"; do
    rm -f "$f" 2>/dev/null || true
  done
}
trap _cleanup EXIT

# ── Formatting ────────────────────────────────────────────────────────────────
BOLD='\033[1m' DIM='\033[2m' RED='\033[31m' GREEN='\033[32m'
YELLOW='\033[33m' CYAN='\033[36m' RESET='\033[0m'

info()    { echo -e "  ${CYAN}::${RESET} $1"; }
success() { echo -e "  ${GREEN}${BOLD}ok${RESET} $1"; }
error()   { echo -e "\n  ${RED}${BOLD}!! ERROR${RESET}${RED} $1${RESET}\n" >&2; }
# ── Interactive selector ─────────────────────────────────────────────────────
# Usage: select_option "Prompt" "label1|desc1" "label2|desc2" ...
# Sets SELECT_RESULT to the 1-based index of the chosen option.
select_option() {
  local prompt="$1"; shift
  local options=("$@")
  local count=${#options[@]}
  local cur=0

  # Hide cursor, restore on exit/interrupt
  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null || true' RETURN

  # Print prompt
  echo -e "  ${CYAN}?${RESET} ${prompt}"

  # Draw all options
  for i in "${!options[@]}"; do
    local label="${options[$i]%%|*}"
    local desc="${options[$i]#*|}"
    if (( i == cur )); then
      echo -e "  ${CYAN}❯${RESET} ${BOLD}${label}${RESET}  ${DIM}${desc}${RESET}"
    else
      echo -e "    ${label}  ${DIM}${desc}${RESET}"
    fi
  done

  # Read keys and redraw
  while true; do
    local key=""
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')  # escape sequence
        IFS= read -rsn2 key
        case "$key" in
          '[A') (( cur > 0 )) && (( cur-- )) || true ;;          # up
          '[B') (( cur < count - 1 )) && (( cur++ )) || true ;;  # down
        esac
        ;;
      '')  # Enter
        break
        ;;
    esac

    # Move cursor up by $count lines and redraw options
    printf '\033[%dA' "$count"
    for i in "${!options[@]}"; do
      local label="${options[$i]%%|*}"
      local desc="${options[$i]#*|}"
      # Clear line then print
      printf '\033[2K'
      if (( i == cur )); then
        echo -e "  ${CYAN}❯${RESET} ${BOLD}${label}${RESET}  ${DIM}${desc}${RESET}"
      else
        echo -e "    ${label}  ${DIM}${desc}${RESET}"
      fi
    done
  done

  # Replace the list with the selected item (move up, clear, print)
  printf '\033[%dA' "$count"
  for (( i = 0; i < count; i++ )); do
    printf '\033[2K'
    if (( i == 0 )); then
      local label="${options[$cur]%%|*}"
      echo -e "  ${GREEN}✔${RESET} ${label}"
    else
      echo ""
    fi
  done
  # Move back up past blank lines
  if (( count > 1 )); then
    printf '\033[%dA' "$((count - 1))"
  fi

  SELECT_RESULT=$(( cur + 1 ))
}

# ── Helpers ───────────────────────────────────────────────────────────────────
# Check if a value exists in an array (bash 3.x compatible)
# Usage: array_contains "value" "${array[@]}"
array_contains() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# ── Config discovery ──────────────────────────────────────────────────────────
# Discover existing FMAPI configuration from settings and helper files.
# Sets CFG_* variables for use by callers.
discover_config() {
  CFG_FOUND=false
  CFG_HOST="" CFG_PROFILE="" CFG_LIFETIME="" CFG_CACHE_FILE=""
  CFG_MODEL="" CFG_OPUS="" CFG_SONNET="" CFG_HAIKU=""
  CFG_SETTINGS_FILE="" CFG_HELPER_FILE=""
  CFG_PAT_EXPIRY_EPOCH="" CFG_PAT_TOKEN=""

  # Find the first settings file with FMAPI config
  for candidate in "$HOME/.claude/settings.json" "./.claude/settings.json"; do
    [[ -f "$candidate" ]] || continue
    local abs_path=""
    abs_path=$(cd "$(dirname "$candidate")" && echo "$(pwd)/$(basename "$candidate")")

    local helper=""
    helper=$(jq -r '.apiKeyHelper // empty' "$abs_path" 2>/dev/null) || true
    [[ -n "$helper" ]] || continue

    CFG_FOUND=true
    CFG_SETTINGS_FILE="$abs_path"
    CFG_HELPER_FILE="$helper"

    # Parse helper script for FMAPI_* variables (supports both FMAPI_* and legacy names)
    if [[ -f "$helper" ]]; then
      CFG_PROFILE=$(sed -n 's/^FMAPI_PROFILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true
      [[ -z "$CFG_PROFILE" ]] && { CFG_PROFILE=$(sed -n 's/^PROFILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true; }
      CFG_HOST=$(sed -n 's/^FMAPI_HOST="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true
      [[ -z "$CFG_HOST" ]] && { CFG_HOST=$(sed -n 's/^HOST="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true; }
      CFG_LIFETIME=$(sed -n 's/^FMAPI_LIFETIME="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true
      [[ -z "$CFG_LIFETIME" ]] && { CFG_LIFETIME=$(sed -n 's/^LIFETIME="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true; }
      CFG_CACHE_FILE=$(sed -n 's/^FMAPI_CACHE_FILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true
      [[ -z "$CFG_CACHE_FILE" ]] && { CFG_CACHE_FILE=$(sed -n 's/^CACHE_FILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true; }
    fi

    # Parse model names from settings.json env block
    CFG_MODEL=$(jq -r '.env.ANTHROPIC_MODEL // empty' "$abs_path" 2>/dev/null) || true
    CFG_OPUS=$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL // empty' "$abs_path" 2>/dev/null) || true
    CFG_SONNET=$(jq -r '.env.ANTHROPIC_DEFAULT_SONNET_MODEL // empty' "$abs_path" 2>/dev/null) || true
    CFG_HAIKU=$(jq -r '.env.ANTHROPIC_DEFAULT_HAIKU_MODEL // empty' "$abs_path" 2>/dev/null) || true

    # Parse cache file for token expiry
    if [[ -n "$CFG_CACHE_FILE" && -f "$CFG_CACHE_FILE" ]]; then
      CFG_PAT_EXPIRY_EPOCH=$(jq -r '.expiry_epoch // empty' "$CFG_CACHE_FILE" 2>/dev/null) || true
      CFG_PAT_TOKEN=$(jq -r '.token // empty' "$CFG_CACHE_FILE" 2>/dev/null) || true
    fi

    break  # Use first match
  done
}

# ── Status ────────────────────────────────────────────────────────────────────
do_status() {
  if ! command -v jq &>/dev/null; then
    error "jq is required for status. Install with: brew install jq"
    exit 1
  fi

  discover_config

  if [[ "$CFG_FOUND" != true ]]; then
    echo -e "\n${BOLD}  FMAPI Status${RESET}\n"
    info "No FMAPI configuration found."
    info "Run ${CYAN}bash setup-fmapi-claudecode.sh${RESET} to set up."
    echo ""
    exit 0
  fi

  echo -e "\n${BOLD}  FMAPI Status${RESET}\n"

  # ── Configuration ─────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Configuration${RESET}"
  echo -e "  ${DIM}Workspace${RESET}  ${BOLD}${CFG_HOST:-unknown}${RESET}"
  echo -e "  ${DIM}Profile${RESET}    ${BOLD}${CFG_PROFILE:-unknown}${RESET}"
  echo -e "  ${DIM}Model${RESET}      ${BOLD}${CFG_MODEL:-unknown}${RESET}"
  echo -e "  ${DIM}Opus${RESET}       ${BOLD}${CFG_OPUS:-unknown}${RESET}"
  echo -e "  ${DIM}Sonnet${RESET}     ${BOLD}${CFG_SONNET:-unknown}${RESET}"
  echo -e "  ${DIM}Haiku${RESET}      ${BOLD}${CFG_HAIKU:-unknown}${RESET}"
  echo ""

  # ── PAT health ────────────────────────────────────────────────────────────
  echo -e "  ${BOLD}PAT Health${RESET}"
  if [[ -n "$CFG_PAT_EXPIRY_EPOCH" ]]; then
    local now remaining_s remaining_h remaining_m
    now=$(date +%s)
    remaining_s=$(( CFG_PAT_EXPIRY_EPOCH - now ))

    if (( remaining_s <= 0 )); then
      echo -e "  ${RED}${BOLD}EXPIRED${RESET}  PAT expired $(date -r "$CFG_PAT_EXPIRY_EPOCH" '+%Y-%m-%d %H:%M %Z')"
    elif (( remaining_s < 7200 )); then
      remaining_m=$(( remaining_s / 60 ))
      echo -e "  ${YELLOW}${BOLD}WARNING${RESET}  ${remaining_m}m remaining (expires $(date -r "$CFG_PAT_EXPIRY_EPOCH" '+%Y-%m-%d %H:%M %Z'))"
    else
      remaining_h=$(( remaining_s / 3600 ))
      remaining_m=$(( (remaining_s % 3600) / 60 ))
      echo -e "  ${GREEN}${BOLD}HEALTHY${RESET}  ${remaining_h}h ${remaining_m}m remaining (expires $(date -r "$CFG_PAT_EXPIRY_EPOCH" '+%Y-%m-%d %H:%M %Z'))"
    fi
  else
    echo -e "  ${RED}${BOLD}UNKNOWN${RESET}  No cache file found"
  fi
  echo ""

  # ── OAuth health ──────────────────────────────────────────────────────────
  echo -e "  ${BOLD}OAuth Health${RESET}"
  if [[ -n "$CFG_PROFILE" ]] && command -v databricks &>/dev/null; then
    local oauth_tok=""
    oauth_tok=$(databricks auth token --profile "$CFG_PROFILE" --output json 2>/dev/null \
      | jq -r '.access_token // empty') || true

    if [[ -n "$oauth_tok" ]]; then
      echo -e "  ${GREEN}${BOLD}ACTIVE${RESET}   OAuth session valid"
    else
      echo -e "  ${RED}${BOLD}EXPIRED${RESET}  Run: ${CYAN}databricks auth login --host ${CFG_HOST} --profile ${CFG_PROFILE}${RESET}"
    fi
  else
    echo -e "  ${DIM}UNKNOWN${RESET}  Cannot check (databricks CLI not found or no profile)"
  fi
  echo ""

  # ── File locations ────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Files${RESET}"
  echo -e "  ${DIM}Settings${RESET}   ${CFG_SETTINGS_FILE}"
  echo -e "  ${DIM}Helper${RESET}     ${CFG_HELPER_FILE}"
  if [[ -n "$CFG_CACHE_FILE" ]]; then
    echo -e "  ${DIM}Cache${RESET}      ${CFG_CACHE_FILE}"
  fi
  echo ""
}

# ── Refresh ───────────────────────────────────────────────────────────────────
do_refresh() {
  if ! command -v jq &>/dev/null; then
    error "jq is required for refresh. Install with: brew install jq"
    exit 1
  fi

  if ! command -v databricks &>/dev/null; then
    error "Databricks CLI is required for refresh. Install with: brew tap databricks/tap && brew install databricks"
    exit 1
  fi

  discover_config

  if [[ "$CFG_FOUND" != true ]]; then
    error "No FMAPI configuration found. Run setup first."
    exit 1
  fi

  [[ -z "$CFG_PROFILE" ]] && { error "Could not determine profile from helper script."; exit 1; }
  [[ -z "$CFG_HOST" ]] && { error "Could not determine host from helper script."; exit 1; }
  [[ -z "$CFG_LIFETIME" ]] && { error "Could not determine PAT lifetime from helper script."; exit 1; }
  [[ -z "$CFG_CACHE_FILE" ]] && { error "Could not determine cache file from helper script."; exit 1; }

  # Check OAuth session — do NOT launch browser, just report
  local oauth_tok=""
  oauth_tok=$(databricks auth token --profile "$CFG_PROFILE" --output json 2>/dev/null \
    | jq -r '.access_token // empty') || true

  if [[ -z "$oauth_tok" ]]; then
    error "OAuth session expired. Re-authenticate first:"
    echo -e "  ${CYAN}databricks auth login --host ${CFG_HOST} --profile ${CFG_PROFILE}${RESET}\n" >&2
    exit 1
  fi

  # Revoke old FMAPI PATs
  local old_ids=""
  old_ids=$(databricks tokens list --profile "$CFG_PROFILE" --output json 2>/dev/null \
    | jq -r '.[] | select((.comment // "") | startswith("Claude Code FMAPI")) | .token_id' 2>/dev/null) || true
  if [[ -n "$old_ids" ]]; then
    while IFS= read -r tid; do
      [[ -n "$tid" ]] && databricks tokens delete "$tid" --profile "$CFG_PROFILE" 2>/dev/null || true
    done <<< "$old_ids"
  fi

  # Create new PAT
  local pat_json="" new_token="" expiry_epoch=""
  pat_json=$(databricks tokens create \
    --lifetime-seconds "$CFG_LIFETIME" \
    --comment "Claude Code FMAPI (created $(date '+%Y-%m-%d'))" \
    --profile "$CFG_PROFILE" \
    --output json)
  new_token=$(echo "$pat_json" | jq -r '.token_value // empty')
  [[ -z "$new_token" ]] && { error "Failed to create PAT."; exit 1; }
  expiry_epoch=$(( $(date +%s) + CFG_LIFETIME ))

  # Update cache atomically
  local tmpfile=""
  tmpfile=$(mktemp "${CFG_CACHE_FILE}.XXXXXX")
  _CLEANUP_FILES+=("$tmpfile")
  jq -n --arg tok "$new_token" --argjson exp "$expiry_epoch" --argjson lt "$CFG_LIFETIME" \
    '{token: $tok, expiry_epoch: $exp, lifetime_seconds: $lt}' > "$tmpfile"
  chmod 600 "$tmpfile"
  mv "$tmpfile" "$CFG_CACHE_FILE"

  success "PAT refreshed (expires $(date -r "$expiry_epoch" '+%Y-%m-%d %H:%M %Z'))."
}

# ── Uninstall ────────────────────────────────────────────────────────────────
do_uninstall() {
  echo -e "\n${BOLD}  Claude Code x Databricks FMAPI — Uninstall${RESET}\n"

  # Require jq
  if ! command -v jq &>/dev/null; then
    error "jq is required for uninstall. Install with: brew install jq"
    exit 1
  fi

  # ── Discover FMAPI artifacts ──────────────────────────────────────────────
  declare -a helper_scripts=()
  declare -a cache_files=()
  declare -a settings_files=()
  declare -a profiles=()
  # Check well-known settings locations for apiKeyHelper or _fmapi_meta
  for candidate in "$HOME/.claude/settings.json" "./.claude/settings.json"; do
    [[ -f "$candidate" ]] || continue
    local abs_path=""
    abs_path=$(cd "$(dirname "$candidate")" && echo "$(pwd)/$(basename "$candidate")")
    if array_contains "$abs_path" ${settings_files[@]+"${settings_files[@]}"}; then
      continue
    fi

    local has_fmapi=false

    # Check for new-style apiKeyHelper
    local helper=""
    helper=$(jq -r '.apiKeyHelper // empty' "$abs_path" 2>/dev/null) || true
    if [[ -n "$helper" ]]; then
      has_fmapi=true
      if [[ -f "$helper" ]]; then
        if ! array_contains "$helper" ${helper_scripts[@]+"${helper_scripts[@]}"}; then
          helper_scripts+=("$helper")
        fi
        # Extract profile from helper script (supports both FMAPI_PROFILE and legacy PROFILE)
        local profile=""
        profile=$(sed -n 's/^FMAPI_PROFILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true
        [[ -z "$profile" ]] && { profile=$(sed -n 's/^PROFILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true; }
        if [[ -n "$profile" ]] && ! array_contains "$profile" ${profiles[@]+"${profiles[@]}"}; then
          profiles+=("$profile")
        fi
        # Find cache file from helper script (supports both FMAPI_CACHE_FILE and legacy CACHE_FILE)
        local cache_file=""
        cache_file=$(sed -n 's/^FMAPI_CACHE_FILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true
        [[ -z "$cache_file" ]] && { cache_file=$(sed -n 's/^CACHE_FILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true; }
        if [[ -n "$cache_file" && -f "$cache_file" ]]; then
          if ! array_contains "$cache_file" ${cache_files[@]+"${cache_files[@]}"}; then
            cache_files+=("$cache_file")
          fi
        fi
      fi
    fi

    # Check for old-style _fmapi_meta (backward compat)
    if jq -e '._fmapi_meta' "$abs_path" &>/dev/null; then
      has_fmapi=true
    fi

    if [[ "$has_fmapi" == true ]]; then
      settings_files+=("$abs_path")
    fi
  done

  # ── Early exit if nothing found ──────────────────────────────────────────
  if [[ ${#helper_scripts[@]} -eq 0 && ${#cache_files[@]} -eq 0 && ${#settings_files[@]} -eq 0 ]]; then
    info "Nothing to uninstall. No FMAPI artifacts found."
    exit 0
  fi

  # ── Display findings ─────────────────────────────────────────────────────
  echo -e "  ${BOLD}Found the following FMAPI artifacts:${RESET}\n"

  if [[ ${#helper_scripts[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}Helper scripts:${RESET}"
    for hs in "${helper_scripts[@]}"; do
      echo -e "    ${DIM}${hs}${RESET}"
    done
    echo ""
  fi

  if [[ ${#cache_files[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}Cache files:${RESET}"
    for cf in "${cache_files[@]}"; do
      echo -e "    ${DIM}${cf}${RESET}"
    done
    echo ""
  fi

  if [[ ${#settings_files[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}Settings files (FMAPI keys only — other settings preserved):${RESET}"
    for sf in "${settings_files[@]}"; do
      echo -e "    ${DIM}${sf}${RESET}"
    done
    echo ""
  fi

  # ── Confirm removal ──────────────────────────────────────────────────────
  select_option "Remove FMAPI artifacts?" \
    "Yes|remove artifacts listed above" \
    "No|cancel and exit"
  [[ "$SELECT_RESULT" -ne 1 ]] && { info "Cancelled."; exit 0; }

  echo ""

  # ── Delete helper scripts and cache files ────────────────────────────────
  for hs in "${helper_scripts[@]}"; do
    rm -f "$hs"
    success "Deleted ${hs}."
  done

  for cf in "${cache_files[@]}"; do
    rm -f "$cf"
    success "Deleted ${cf}."
  done

  # ── Clean settings files ─────────────────────────────────────────────────
  local fmapi_env_keys='["ANTHROPIC_MODEL","ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_DEFAULT_OPUS_MODEL","ANTHROPIC_DEFAULT_SONNET_MODEL","ANTHROPIC_DEFAULT_HAIKU_MODEL","ANTHROPIC_CUSTOM_HEADERS","CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS","CLAUDE_CODE_API_KEY_HELPER_TTL_MS"]'

  for sf in "${settings_files[@]}"; do
    local tmpfile=""
    tmpfile=$(mktemp "${sf}.XXXXXX")
    _CLEANUP_FILES+=("$tmpfile")
    jq --argjson keys "$fmapi_env_keys" '
      .env = ((.env // {}) | to_entries | map(select(.key as $k | $keys | index($k) | not)) | from_entries)
      | del(._fmapi_meta)
      | del(.apiKeyHelper)
      | if .env == {} then del(.env) else . end
    ' "$sf" > "$tmpfile"
    chmod 600 "$tmpfile"

    # Check if file is now empty ({})
    local remaining=""
    remaining=$(jq 'length' "$tmpfile")
    if [[ "$remaining" == "0" ]]; then
      rm -f "$tmpfile" "$sf"
      success "Deleted ${sf} (no remaining settings)."
    else
      mv "$tmpfile" "$sf"
      success "Cleaned FMAPI keys from ${sf} (preserved other settings)."
    fi
  done

  # ── Optionally revoke PATs ──────────────────────────────────────────────
  if [[ ${#profiles[@]} -gt 0 ]]; then
    echo ""
    select_option "Revoke FMAPI PATs from Databricks?" \
      "Yes|revoke PATs with comment starting with \"Claude Code FMAPI\"" \
      "No|skip (tokens will expire on their own)"

    if [[ "$SELECT_RESULT" -eq 1 ]]; then
      if ! command -v databricks &>/dev/null; then
        info "Databricks CLI not found. Skipping PAT revocation (tokens will expire naturally)."
      else
        for profile in "${profiles[@]}"; do
          # Verify OAuth session
          local oauth_tok=""
          oauth_tok=$(databricks auth token --profile "$profile" --output json 2>/dev/null \
            | jq -r '.access_token // empty') || true

          if [[ -z "$oauth_tok" ]]; then
            info "No active OAuth session for profile '${profile}'. Skipping PAT revocation for this profile."
            continue
          fi

          local pat_ids=""
          pat_ids=$(databricks tokens list --profile "$profile" --output json 2>/dev/null \
            | jq -r '.[] | select((.comment // "") | startswith("Claude Code FMAPI")) | .token_id' 2>/dev/null) || true

          if [[ -z "$pat_ids" ]]; then
            info "No FMAPI PATs found for profile '${profile}'."
            continue
          fi

          local count=0
          while IFS= read -r tid; do
            if [[ -n "$tid" ]]; then
              databricks tokens delete "$tid" --profile "$profile" 2>/dev/null || true
              (( count++ )) || true
            fi
          done <<< "$pat_ids"
          success "Revoked ${count} FMAPI PAT(s) for profile '${profile}'."
        done
      fi
    fi
  fi

  # ── Remove plugin registration ─────────────────────────────────────────
  local plugins_file="$HOME/.claude/plugins/installed_plugins.json"
  if [[ -f "$plugins_file" ]] && jq -e '.["fmapi-codingagent"]' "$plugins_file" &>/dev/null; then
    local ptmp=""
    ptmp=$(mktemp "${plugins_file}.XXXXXX")
    _CLEANUP_FILES+=("$ptmp")
    jq 'del(.["fmapi-codingagent"])' "$plugins_file" > "$ptmp"
    local plen=""
    plen=$(jq 'length' "$ptmp")
    if [[ "$plen" == "0" ]]; then
      rm -f "$ptmp" "$plugins_file"
      success "Removed plugin registration (file deleted — no other plugins)."
    else
      mv "$ptmp" "$plugins_file"
      success "Removed plugin registration from ${plugins_file}."
    fi
  fi

  # ── Summary ──────────────────────────────────────────────────────────────
  echo -e "\n${GREEN}${BOLD}  Uninstall complete!${RESET}\n"
}

# ── CLI flag parsing ──────────────────────────────────────────────────────────
CLI_HOST="" CLI_PROFILE="" CLI_MODEL="" CLI_OPUS="" CLI_SONNET="" CLI_HAIKU=""
CLI_SETTINGS_LOCATION="" CLI_PAT_LIFETIME=""
ACTION=""

show_help() {
  cat <<'HELPTEXT'
Usage: bash setup-fmapi-claudecode.sh [OPTIONS]

Sets up Claude Code to use Databricks Foundation Model API.
Installs prerequisites automatically (Homebrew, jq, Claude Code, Databricks CLI).

Commands:
  --status              Show FMAPI configuration health dashboard
  --refresh             Rotate PAT token (non-interactive)
  --uninstall           Remove FMAPI helper scripts, settings, and optionally revoke PATs
  -h, --help            Show this help message

Setup options (skip interactive prompts):
  --host URL            Databricks workspace URL (e.g. https://my-workspace.cloud.databricks.com)
  --profile NAME        Databricks CLI profile name
  --model MODEL         Primary model (default: databricks-claude-opus-4-6)
  --opus MODEL          Opus model (default: databricks-claude-opus-4-6)
  --sonnet MODEL        Sonnet model (default: databricks-claude-sonnet-4-6)
  --haiku MODEL         Haiku model (default: databricks-claude-haiku-4-5)
  --settings-location PATH
                        Where to write settings: "home", "cwd", or a custom path
  --pat-lifetime DAYS   PAT lifetime in days: 1, 3, 5, or 7

Examples:
  # Interactive setup (prompts for all values)
  bash setup-fmapi-claudecode.sh

  # Non-interactive setup (all values from flags)
  bash setup-fmapi-claudecode.sh --host https://my-workspace.cloud.databricks.com --profile my-profile

  # Check configuration health
  bash setup-fmapi-claudecode.sh --status

  # Rotate PAT token
  bash setup-fmapi-claudecode.sh --refresh

  # Uninstall
  bash setup-fmapi-claudecode.sh --uninstall
HELPTEXT
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)      show_help ;;
    --status)       ACTION="status"; shift ;;
    --refresh)      ACTION="refresh"; shift ;;
    --uninstall)    ACTION="uninstall"; shift ;;
    --host)         CLI_HOST="${2:-}"; [[ -z "$CLI_HOST" ]] && { error "--host requires a URL."; exit 1; }; shift 2 ;;
    --profile)      CLI_PROFILE="${2:-}"; [[ -z "$CLI_PROFILE" ]] && { error "--profile requires a name."; exit 1; }; shift 2 ;;
    --model)        CLI_MODEL="${2:-}"; [[ -z "$CLI_MODEL" ]] && { error "--model requires a value."; exit 1; }; shift 2 ;;
    --opus)         CLI_OPUS="${2:-}"; [[ -z "$CLI_OPUS" ]] && { error "--opus requires a value."; exit 1; }; shift 2 ;;
    --sonnet)       CLI_SONNET="${2:-}"; [[ -z "$CLI_SONNET" ]] && { error "--sonnet requires a value."; exit 1; }; shift 2 ;;
    --haiku)        CLI_HAIKU="${2:-}"; [[ -z "$CLI_HAIKU" ]] && { error "--haiku requires a value."; exit 1; }; shift 2 ;;
    --settings-location) CLI_SETTINGS_LOCATION="${2:-}"; [[ -z "$CLI_SETTINGS_LOCATION" ]] && { error "--settings-location requires a value."; exit 1; }; shift 2 ;;
    --pat-lifetime) CLI_PAT_LIFETIME="${2:-}"; [[ -z "$CLI_PAT_LIFETIME" ]] && { error "--pat-lifetime requires a value."; exit 1; }; shift 2 ;;
    *)              error "Unknown option: $1"; echo "  Run with --help for usage." >&2; exit 1 ;;
  esac
done

# ── Dispatch commands ─────────────────────────────────────────────────────────
case "${ACTION}" in
  status)    do_status; exit 0 ;;
  refresh)   do_refresh; exit 0 ;;
  uninstall) do_uninstall; exit 0 ;;
esac

# ── Banner & prompts ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}  Claude Code x Databricks FMAPI Setup${RESET}\n"

# Initialize CFG_* defaults (discover_config sets these, but jq may not be available yet)
CFG_FOUND=false CFG_HOST="" CFG_PROFILE="" CFG_LIFETIME="" CFG_CACHE_FILE=""
CFG_MODEL="" CFG_OPUS="" CFG_SONNET="" CFG_HAIKU=""
CFG_SETTINGS_FILE="" CFG_HELPER_FILE="" CFG_PAT_EXPIRY_EPOCH="" CFG_PAT_TOKEN=""

# Discover existing config for defaults
if command -v jq &>/dev/null; then
  discover_config
fi

# Helper: resolve default value — CLI flag > discovered config > hardcoded default
_default() { echo "${1:-${2:-${3:-}}}"; }

DEFAULT_HOST=$(_default "$CLI_HOST" "$CFG_HOST")
DEFAULT_PROFILE=$(_default "$CLI_PROFILE" "$CFG_PROFILE")
DEFAULT_MODEL=$(_default "$CLI_MODEL" "$CFG_MODEL" "databricks-claude-opus-4-6")
DEFAULT_OPUS=$(_default "$CLI_OPUS" "$CFG_OPUS" "databricks-claude-opus-4-6")
DEFAULT_SONNET=$(_default "$CLI_SONNET" "$CFG_SONNET" "databricks-claude-sonnet-4-6")
DEFAULT_HAIKU=$(_default "$CLI_HAIKU" "$CFG_HAIKU" "databricks-claude-haiku-4-5")

# ── Workspace URL ───────────────────────────────────────────────────────────
if [[ -n "$CLI_HOST" ]]; then
  DATABRICKS_HOST="$CLI_HOST"
else
  if [[ -n "$DEFAULT_HOST" ]]; then
    read -rp "$(echo -e "  ${CYAN}?${RESET} Databricks workspace URL ${DIM}[${DEFAULT_HOST}]${RESET}: ")" DATABRICKS_HOST
    DATABRICKS_HOST="${DATABRICKS_HOST:-$DEFAULT_HOST}"
  else
    read -rp "$(echo -e "  ${CYAN}?${RESET} Databricks workspace URL: ")" DATABRICKS_HOST
  fi
fi
[[ -z "$DATABRICKS_HOST" ]] && { error "Workspace URL is required."; exit 1; }
DATABRICKS_HOST="${DATABRICKS_HOST%/}"
[[ "$DATABRICKS_HOST" != https://* ]] && { error "Workspace URL must start with https://"; exit 1; }

# ── CLI profile ─────────────────────────────────────────────────────────────
if [[ -n "$CLI_PROFILE" ]]; then
  DATABRICKS_PROFILE="$CLI_PROFILE"
else
  if [[ -n "$DEFAULT_PROFILE" ]]; then
    read -rp "$(echo -e "  ${CYAN}?${RESET} Databricks CLI profile name ${DIM}[${DEFAULT_PROFILE}]${RESET}: ")" DATABRICKS_PROFILE
    DATABRICKS_PROFILE="${DATABRICKS_PROFILE:-$DEFAULT_PROFILE}"
  else
    read -rp "$(echo -e "  ${CYAN}?${RESET} Databricks CLI profile name: ")" DATABRICKS_PROFILE
  fi
fi
[[ -z "$DATABRICKS_PROFILE" ]] && { error "Profile name is required."; exit 1; }
[[ "$DATABRICKS_PROFILE" =~ ^[a-zA-Z0-9_-]+$ ]] || { error "Invalid profile name: '$DATABRICKS_PROFILE'. Use letters, numbers, hyphens, and underscores."; exit 1; }

# ── Models ──────────────────────────────────────────────────────────────────
if [[ -n "$CLI_MODEL" ]]; then
  ANTHROPIC_MODEL="$CLI_MODEL"
else
  read -rp "$(echo -e "  ${CYAN}?${RESET} Model ${DIM}[${DEFAULT_MODEL}]${RESET}: ")" ANTHROPIC_MODEL
  ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-$DEFAULT_MODEL}"
fi

if [[ -n "$CLI_OPUS" ]]; then
  ANTHROPIC_OPUS_MODEL="$CLI_OPUS"
else
  read -rp "$(echo -e "  ${CYAN}?${RESET} Opus model ${DIM}[${DEFAULT_OPUS}]${RESET}: ")" ANTHROPIC_OPUS_MODEL
  ANTHROPIC_OPUS_MODEL="${ANTHROPIC_OPUS_MODEL:-$DEFAULT_OPUS}"
fi

if [[ -n "$CLI_SONNET" ]]; then
  ANTHROPIC_SONNET_MODEL="$CLI_SONNET"
else
  read -rp "$(echo -e "  ${CYAN}?${RESET} Sonnet model ${DIM}[${DEFAULT_SONNET}]${RESET}: ")" ANTHROPIC_SONNET_MODEL
  ANTHROPIC_SONNET_MODEL="${ANTHROPIC_SONNET_MODEL:-$DEFAULT_SONNET}"
fi

if [[ -n "$CLI_HAIKU" ]]; then
  ANTHROPIC_HAIKU_MODEL="$CLI_HAIKU"
else
  read -rp "$(echo -e "  ${CYAN}?${RESET} Haiku model ${DIM}[${DEFAULT_HAIKU}]${RESET}: ")" ANTHROPIC_HAIKU_MODEL
  ANTHROPIC_HAIKU_MODEL="${ANTHROPIC_HAIKU_MODEL:-$DEFAULT_HAIKU}"
fi

# ── Settings location ───────────────────────────────────────────────────────
if [[ -n "$CLI_SETTINGS_LOCATION" ]]; then
  case "$CLI_SETTINGS_LOCATION" in
    home) SETTINGS_BASE="$HOME" ;;
    cwd)  SETTINGS_BASE="$(cd "$(pwd)" && pwd)" ;;
    *)
      CLI_SETTINGS_LOCATION="${CLI_SETTINGS_LOCATION/#\~/$HOME}"
      mkdir -p "$CLI_SETTINGS_LOCATION"
      SETTINGS_BASE="$(cd "$CLI_SETTINGS_LOCATION" && pwd)"
      ;;
  esac
else
  select_option "Settings location" \
    "Home directory|~/.claude/settings.json, default" \
    "Current directory|./.claude/settings.json" \
    "Custom path|enter your own path"
  SETTINGS_CHOICE="$SELECT_RESULT"

  case "$SETTINGS_CHOICE" in
    1)
      SETTINGS_BASE="$HOME"
      ;;
    2)
      SETTINGS_BASE="$(cd "$(pwd)" && pwd)"
      ;;
    3)
      read -rp "$(echo -e "  ${CYAN}?${RESET} Base path: ")" CUSTOM_PATH
      [[ -z "$CUSTOM_PATH" ]] && { error "Custom path is required."; exit 1; }
      CUSTOM_PATH="${CUSTOM_PATH/#\~/$HOME}"
      mkdir -p "$CUSTOM_PATH"
      SETTINGS_BASE="$(cd "$CUSTOM_PATH" && pwd)"
      ;;
  esac
fi

# ── PAT lifetime ────────────────────────────────────────────────────────────
if [[ -n "$CLI_PAT_LIFETIME" ]]; then
  case "$CLI_PAT_LIFETIME" in
    1) PAT_LIFETIME_SECONDS=86400;  PAT_LIFETIME_LABEL="1 day" ;;
    3) PAT_LIFETIME_SECONDS=259200; PAT_LIFETIME_LABEL="3 days" ;;
    5) PAT_LIFETIME_SECONDS=432000; PAT_LIFETIME_LABEL="5 days" ;;
    7) PAT_LIFETIME_SECONDS=604800; PAT_LIFETIME_LABEL="7 days" ;;
    *) error "Invalid --pat-lifetime: $CLI_PAT_LIFETIME. Use 1, 3, 5, or 7."; exit 1 ;;
  esac
else
  select_option "PAT lifetime" \
    "1 day|default" \
    "3 days|" \
    "5 days|" \
    "7 days|"
  PAT_LIFE_CHOICE="$SELECT_RESULT"

  case "$PAT_LIFE_CHOICE" in
    1) PAT_LIFETIME_SECONDS=86400;  PAT_LIFETIME_LABEL="1 day" ;;
    2) PAT_LIFETIME_SECONDS=259200; PAT_LIFETIME_LABEL="3 days" ;;
    3) PAT_LIFETIME_SECONDS=432000; PAT_LIFETIME_LABEL="5 days" ;;
    4) PAT_LIFETIME_SECONDS=604800; PAT_LIFETIME_LABEL="7 days" ;;
  esac
fi

SETTINGS_FILE="${SETTINGS_BASE}/.claude/settings.json"
HELPER_FILE="${SETTINGS_BASE}/.claude/fmapi-key-helper.sh"
CACHE_FILE="${SETTINGS_BASE}/.claude/.fmapi-pat-cache"

# ── Install dependencies ─────────────────────────────────────────────────────
echo -e "\n${BOLD}Installing dependencies${RESET}"

# Homebrew
if command -v brew &>/dev/null; then
  success "Homebrew already installed."
else
  info "Installing Homebrew ..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for this session (needed on fresh installs)
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  success "Homebrew installed."
fi

# jq
if command -v jq &>/dev/null; then
  success "jq already installed."
else
  info "Installing jq ..."
  brew install jq
  success "jq installed."
fi

if command -v claude &>/dev/null; then
  success "Claude Code already installed."
else
  info "Installing Claude Code ..."
  curl -fsSL https://claude.ai/install.sh | bash
  success "Claude Code installed."
fi

if command -v databricks &>/dev/null; then
  success "Databricks CLI already installed."
else
  info "Installing Databricks CLI ..."
  brew tap databricks/tap && brew install databricks
  success "Databricks CLI installed."
fi

# ── Authenticate ──────────────────────────────────────────────────────────────
echo -e "\n${BOLD}Authenticating${RESET}"

get_oauth_token() {
  databricks auth token --profile "$DATABRICKS_PROFILE" --output json 2>/dev/null \
    | jq -r '.access_token // empty'
}

# OAuth login is required (PAT creation needs an active session)
OAUTH_TOKEN=$(get_oauth_token) || true
if [[ -z "$OAUTH_TOKEN" ]]; then
  info "Logging in to ${DATABRICKS_HOST} ..."
  databricks auth login --host "$DATABRICKS_HOST" --profile "$DATABRICKS_PROFILE"
  OAUTH_TOKEN=$(get_oauth_token)
fi

[[ -z "$OAUTH_TOKEN" ]] && { error "Failed to get OAuth access token."; exit 1; }
success "OAuth session established."

info "Revoking old FMAPI PATs ..."
OLD_PAT_IDS=$(databricks tokens list --profile "$DATABRICKS_PROFILE" --output json 2>/dev/null \
  | jq -r '.[] | select((.comment // "") | startswith("Claude Code FMAPI")) | .token_id' 2>/dev/null) || true
if [[ -n "$OLD_PAT_IDS" ]]; then
  while IFS= read -r tid; do
    [[ -n "$tid" ]] && databricks tokens delete "$tid" --profile "$DATABRICKS_PROFILE" 2>/dev/null || true
  done <<< "$OLD_PAT_IDS"
  success "Old PATs revoked."
fi

info "Creating PAT (lifetime: ${PAT_LIFETIME_LABEL}) ..."
PAT_JSON=$(databricks tokens create \
  --lifetime-seconds "$PAT_LIFETIME_SECONDS" \
  --comment "Claude Code FMAPI (created $(date '+%Y-%m-%d'))" \
  --profile "$DATABRICKS_PROFILE" \
  --output json)
INITIAL_PAT=$(echo "$PAT_JSON" | jq -r '.token_value // empty')
[[ -z "$INITIAL_PAT" ]] && { error "Failed to create PAT."; exit 1; }
PAT_EXPIRY_EPOCH=$(( $(date +%s) + PAT_LIFETIME_SECONDS ))
success "PAT created (expires: $(date -r "$PAT_EXPIRY_EPOCH" '+%Y-%m-%d %H:%M %Z'))."

# ── Write .claude/settings.json ──────────────────────────────────────────────
echo -e "\n${BOLD}Writing settings${RESET}"

mkdir -p "$(dirname "$SETTINGS_FILE")"

# Compute TTL: half of PAT lifetime in milliseconds, capped at 1 hour
TTL_MS=$(( PAT_LIFETIME_SECONDS * 500 ))
(( TTL_MS > 3600000 )) && TTL_MS=3600000

env_json=$(jq -n \
  --arg model "$ANTHROPIC_MODEL" \
  --arg base  "${DATABRICKS_HOST}/serving-endpoints/anthropic" \
  --arg opus "$ANTHROPIC_OPUS_MODEL" \
  --arg sonnet "$ANTHROPIC_SONNET_MODEL" \
  --arg haiku "$ANTHROPIC_HAIKU_MODEL" \
  --arg ttl "$TTL_MS" \
  '{
    "ANTHROPIC_MODEL": $model,
    "ANTHROPIC_BASE_URL": $base,
    "ANTHROPIC_DEFAULT_OPUS_MODEL": $opus,
    "ANTHROPIC_DEFAULT_SONNET_MODEL": $sonnet,
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": $haiku,
    "ANTHROPIC_CUSTOM_HEADERS": "x-databricks-use-coding-agent-mode: true",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
    "CLAUDE_CODE_API_KEY_HELPER_TTL_MS": $ttl
  }')

if [[ -f "$SETTINGS_FILE" ]]; then
  tmpfile=$(mktemp "${SETTINGS_FILE}.XXXXXX")
  _CLEANUP_FILES+=("$tmpfile")
  jq --argjson new_env "$env_json" --arg helper "$HELPER_FILE" \
    '.env = ((.env // {}) * $new_env | del(.ANTHROPIC_AUTH_TOKEN)) | .apiKeyHelper = $helper | del(._fmapi_meta)' \
    "$SETTINGS_FILE" > "$tmpfile"
  chmod 600 "$tmpfile"
  mv "$tmpfile" "$SETTINGS_FILE"
else
  jq -n --argjson env "$env_json" --arg helper "$HELPER_FILE" \
    '{"apiKeyHelper": $helper, "env": $env}' > "$SETTINGS_FILE"
  chmod 600 "$SETTINGS_FILE"
fi
success "Settings written to ${SETTINGS_FILE}."

# ── Write API key helper script ──────────────────────────────────────────────
echo -e "\n${BOLD}API key helper${RESET}"

cat > "$HELPER_FILE" << 'HELPER_SCRIPT'
#!/bin/sh
set -eu
umask 077

# Temp file cleanup on exit/interrupt
_cleanup_tmp=""
_cleanup() { [ -n "$_cleanup_tmp" ] && rm -f "$_cleanup_tmp" 2>/dev/null || true; }
trap _cleanup EXIT INT TERM

FMAPI_PROFILE="__PROFILE__"
FMAPI_HOST="__HOST__"
FMAPI_LIFETIME="__LIFETIME__"
FMAPI_CACHE_FILE="__CACHE_FILE__"

get_cached_token() {
  [ -f "$FMAPI_CACHE_FILE" ] || return 1
  token=$(jq -r '.token // empty' "$FMAPI_CACHE_FILE" 2>/dev/null) || return 1
  expiry=$(jq -r '.expiry_epoch // 0' "$FMAPI_CACHE_FILE" 2>/dev/null) || return 1
  now=$(date +%s)
  # Return cached token if still valid with 5-minute buffer
  if [ -n "$token" ] && [ "$now" -lt "$((expiry - 300))" ]; then
    echo "$token"
    return 0
  fi
  return 1
}

create_pat() {
  # Check OAuth session
  oauth_tok=$(databricks auth token --profile "$FMAPI_PROFILE" --output json 2>/dev/null \
    | jq -r '.access_token // empty') || true
  if [ -z "$oauth_tok" ]; then
    # Determine best output destination: /dev/tty for direct terminal visibility,
    # fall back to stderr for portability (Windows, CI, non-interactive sessions)
    if [ -e /dev/tty ]; then
      _reauth_out="/dev/tty"
    else
      _reauth_out="/dev/stderr"
    fi
    echo "FMAPI: OAuth session expired — attempting re-authentication ..." > "$_reauth_out"
    if databricks auth login --host "$FMAPI_HOST" --profile "$FMAPI_PROFILE" > "$_reauth_out" 2>&1; then
      oauth_tok=$(databricks auth token --profile "$FMAPI_PROFILE" --output json 2>/dev/null \
        | jq -r '.access_token // empty') || true
      if [ -z "$oauth_tok" ]; then
        echo "FMAPI: Re-authentication failed. Run manually: databricks auth login --host $FMAPI_HOST --profile $FMAPI_PROFILE" > "$_reauth_out"
        exit 1
      fi
      echo "FMAPI: Re-authentication successful." > "$_reauth_out"
    else
      echo "FMAPI: Re-authentication failed. Run manually: databricks auth login --host $FMAPI_HOST --profile $FMAPI_PROFILE" > "$_reauth_out"
      exit 1
    fi
  fi

  # Revoke old FMAPI PATs before creating new one
  databricks tokens list --profile "$FMAPI_PROFILE" --output json 2>/dev/null \
    | jq -r '.[] | select((.comment // "") | startswith("Claude Code FMAPI")) | .token_id' 2>/dev/null \
    | while IFS= read -r tid; do
        [ -n "$tid" ] && databricks tokens delete "$tid" --profile "$FMAPI_PROFILE" 2>/dev/null || true
      done

  # Create new PAT
  pat_json=$(databricks tokens create \
    --lifetime-seconds "$FMAPI_LIFETIME" \
    --comment "Claude Code FMAPI (created $(date '+%Y-%m-%d'))" \
    --profile "$FMAPI_PROFILE" \
    --output json)
  token=$(echo "$pat_json" | jq -r '.token_value // empty')

  if [ -z "$token" ]; then
    echo "FMAPI: Failed to create PAT." >&2
    exit 1
  fi

  # Write cache atomically
  expiry=$(($(date +%s) + FMAPI_LIFETIME))
  tmpfile=$(mktemp "${FMAPI_CACHE_FILE}.XXXXXX")
  _cleanup_tmp="$tmpfile"
  jq -n --arg tok "$token" --argjson exp "$expiry" --argjson lt "$FMAPI_LIFETIME" \
    '{token: $tok, expiry_epoch: $exp, lifetime_seconds: $lt}' > "$tmpfile"
  chmod 600 "$tmpfile"
  mv "$tmpfile" "$FMAPI_CACHE_FILE"
  _cleanup_tmp=""

  echo "$token"
}

# Main: use cached token or create a new one
get_cached_token || create_pat
HELPER_SCRIPT

sed -i '' "s|__PROFILE__|${DATABRICKS_PROFILE}|g; s|__HOST__|${DATABRICKS_HOST}|g; s|__LIFETIME__|${PAT_LIFETIME_SECONDS}|g; s|__CACHE_FILE__|${CACHE_FILE}|g" "$HELPER_FILE"
chmod 700 "$HELPER_FILE"
success "Helper script written to ${HELPER_FILE}."

# ── Seed cache file ──────────────────────────────────────────────────────────
info "Seeding PAT cache ..."
seed_tmp=$(mktemp "${CACHE_FILE}.XXXXXX")
_CLEANUP_FILES+=("$seed_tmp")
jq -n --arg tok "$INITIAL_PAT" --argjson exp "$PAT_EXPIRY_EPOCH" --argjson lt "$PAT_LIFETIME_SECONDS" \
  '{token: $tok, expiry_epoch: $exp, lifetime_seconds: $lt}' > "$seed_tmp"
chmod 600 "$seed_tmp"
mv "$seed_tmp" "$CACHE_FILE"
success "Cache seeded at ${CACHE_FILE}."

# ── Self-install plugin ───────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/.claude-plugin/plugin.json" ]]; then
  PLUGINS_FILE="$HOME/.claude/plugins/installed_plugins.json"
  mkdir -p "$(dirname "$PLUGINS_FILE")"

  NEEDS_INSTALL=true
  if [[ -f "$PLUGINS_FILE" ]]; then
    existing_path=$(jq -r '.["fmapi-codingagent"].installPath // empty' "$PLUGINS_FILE" 2>/dev/null) || true
    [[ "$existing_path" == "$SCRIPT_DIR" ]] && NEEDS_INSTALL=false
  fi

  if [[ "$NEEDS_INSTALL" == true ]]; then
    if [[ -f "$PLUGINS_FILE" ]]; then
      plugin_tmp=$(mktemp "${PLUGINS_FILE}.XXXXXX")
      _CLEANUP_FILES+=("$plugin_tmp")
      jq --arg path "$SCRIPT_DIR" \
        '.["fmapi-codingagent"] = {"scope": "user", "installPath": $path}' \
        "$PLUGINS_FILE" > "$plugin_tmp"
      mv "$plugin_tmp" "$PLUGINS_FILE"
    else
      jq -n --arg path "$SCRIPT_DIR" \
        '{"fmapi-codingagent": {"scope": "user", "installPath": $path}}' > "$PLUGINS_FILE"
    fi
    success "Plugin registered (skills: /fmapi-codingagent-status, /fmapi-codingagent-refresh, /fmapi-codingagent-setup)."
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}  Setup complete!${RESET}"
echo -e "  ${DIM}Workspace${RESET}  ${BOLD}${DATABRICKS_HOST}${RESET}"
echo -e "  ${DIM}Profile${RESET}    ${BOLD}${DATABRICKS_PROFILE}${RESET}"
echo -e "  ${DIM}Model${RESET}      ${BOLD}${ANTHROPIC_MODEL}${RESET}"
echo -e "  ${DIM}Opus${RESET}       ${BOLD}${ANTHROPIC_OPUS_MODEL}${RESET}"
echo -e "  ${DIM}Sonnet${RESET}     ${BOLD}${ANTHROPIC_SONNET_MODEL}${RESET}"
echo -e "  ${DIM}Haiku${RESET}      ${BOLD}${ANTHROPIC_HAIKU_MODEL}${RESET}"
echo -e "  ${DIM}Auth${RESET}       ${BOLD}PAT (${PAT_LIFETIME_LABEL}, expires $(date -r "$PAT_EXPIRY_EPOCH" '+%Y-%m-%d %H:%M %Z'))${RESET}"
echo -e "  ${DIM}Helper${RESET}     ${BOLD}${HELPER_FILE}${RESET}"
echo -e "  ${DIM}Settings${RESET}   ${BOLD}${SETTINGS_FILE}${RESET}"
echo -e "\n  Run ${CYAN}${BOLD}claude${RESET} to start.\n"
