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
  declare -a wrapper_entries=()   # legacy: "rc_file|cmd_name"

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
        # Extract profile from helper script
        local profile=""
        profile=$(sed -n 's/^PROFILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true
        if [[ -n "$profile" ]] && ! array_contains "$profile" ${profiles[@]+"${profiles[@]}"}; then
          profiles+=("$profile")
        fi
        # Find cache file from helper script
        local cache_file=""
        cache_file=$(sed -n 's/^CACHE_FILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true
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

  # Check RC files for legacy wrapper blocks
  local rc_files=("$HOME/.zshrc" "$HOME/.bashrc")
  for rc in "${rc_files[@]}"; do
    [[ -f "$rc" ]] || continue
    while IFS= read -r marker_line; do
      local cmd_name=""
      cmd_name=$(echo "$marker_line" | sed -n 's/^# >>> \(.*\) wrapper >>>$/\1/p')
      [[ -z "$cmd_name" ]] && continue

      wrapper_entries+=("${rc}|${cmd_name}")

      # Extract profile from the wrapper block
      local end_marker="# <<< ${cmd_name} wrapper <<<"
      local profile=""
      profile=$(sed -n "/# >>> ${cmd_name} wrapper >>>/,/${end_marker}/{ s/.*profile=\"\([^\"]*\)\".*/\1/p; }" "$rc" | head -1) || true
      if [[ -n "$profile" ]] && ! array_contains "$profile" ${profiles[@]+"${profiles[@]}"}; then
        profiles+=("$profile")
      fi

      # Extract settings file from wrapper block
      local sf=""
      sf=$(sed -n "/# >>> ${cmd_name} wrapper >>>/,/${end_marker}/{ s/.*local sf=\"\([^\"]*\)\".*/\1/p; }" "$rc" | head -1) || true
      if [[ -n "$sf" ]]; then
        sf="${sf/#\~/$HOME}"
        if [[ -f "$sf" ]]; then
          local abs_sf=""
          abs_sf=$(cd "$(dirname "$sf")" && echo "$(pwd)/$(basename "$sf")")
          if ! array_contains "$abs_sf" ${settings_files[@]+"${settings_files[@]}"}; then
            if jq -e '._fmapi_meta' "$abs_sf" &>/dev/null; then
              settings_files+=("$abs_sf")
            fi
          fi
        fi
      fi
    done < <(grep -n '# >>> .* wrapper >>>' "$rc" 2>/dev/null | sed 's/^[0-9]*://')
  done

  # ── Early exit if nothing found ──────────────────────────────────────────
  if [[ ${#helper_scripts[@]} -eq 0 && ${#cache_files[@]} -eq 0 && ${#settings_files[@]} -eq 0 && ${#wrapper_entries[@]} -eq 0 ]]; then
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

  if [[ ${#wrapper_entries[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}Legacy shell wrappers:${RESET}"
    for entry in "${wrapper_entries[@]}"; do
      local rc="" cmd=""
      rc=$(echo "$entry" | cut -d'|' -f1)
      cmd=$(echo "$entry" | cut -d'|' -f2)
      echo -e "    ${BOLD}${cmd}${RESET} in ${DIM}${rc}${RESET}"
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

  # ── Remove legacy wrapper blocks ────────────────────────────────────────
  for entry in "${wrapper_entries[@]}"; do
    local rc="" cmd=""
    rc=$(echo "$entry" | cut -d'|' -f1)
    cmd=$(echo "$entry" | cut -d'|' -f2)
    local begin="# >>> ${cmd} wrapper >>>"
    local end="# <<< ${cmd} wrapper <<<"
    if grep -qF "$begin" "$rc" 2>/dev/null; then
      sed -i '' "/$begin/,/$end/d" "$rc"
      success "Removed legacy ${cmd} wrapper from ${rc}."
    fi
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

  # ── Summary ──────────────────────────────────────────────────────────────
  echo -e "\n${GREEN}${BOLD}  Uninstall complete!${RESET}\n"
}

# ── Help ──────────────────────────────────────────────────────────────────────
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
  echo "Usage: bash setup-fmapi-claudecode.sh [--uninstall] [-h|--help]"
  echo ""
  echo "Sets up Claude Code to use Databricks Foundation Model API."
  echo "Installs prerequisites automatically (Homebrew, jq, Claude Code, Databricks CLI)."
  echo ""
  echo "Options:"
  echo "  --uninstall   Remove FMAPI helper scripts, settings, and optionally revoke PATs"
  echo "  -h, --help    Show this help message"
  exit 0
}

[[ "${1:-}" == "--uninstall" ]] && {
  do_uninstall
  exit 0
}

# ── Banner & prompts ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}  Claude Code x Databricks FMAPI Setup${RESET}\n"

read -rp "$(echo -e "  ${CYAN}?${RESET} Databricks workspace URL: ")" DATABRICKS_HOST
[[ -z "$DATABRICKS_HOST" ]] && { error "Workspace URL is required."; exit 1; }
DATABRICKS_HOST="${DATABRICKS_HOST%/}"
[[ "$DATABRICKS_HOST" != https://* ]] && { error "Workspace URL must start with https://"; exit 1; }

read -rp "$(echo -e "  ${CYAN}?${RESET} Databricks CLI profile name: ")" DATABRICKS_PROFILE
[[ -z "$DATABRICKS_PROFILE" ]] && { error "Profile name is required."; exit 1; }
[[ "$DATABRICKS_PROFILE" =~ ^[a-zA-Z0-9_-]+$ ]] || { error "Invalid profile name: '$DATABRICKS_PROFILE'. Use letters, numbers, hyphens, and underscores."; exit 1; }

read -rp "$(echo -e "  ${CYAN}?${RESET} Model ${DIM}[databricks-claude-opus-4-6]${RESET}: ")" ANTHROPIC_MODEL
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-databricks-claude-opus-4-6}"

read -rp "$(echo -e "  ${CYAN}?${RESET} Opus model ${DIM}[databricks-claude-opus-4-6]${RESET}: ")" ANTHROPIC_OPUS_MODEL
ANTHROPIC_OPUS_MODEL="${ANTHROPIC_OPUS_MODEL:-databricks-claude-opus-4-6}"

read -rp "$(echo -e "  ${CYAN}?${RESET} Sonnet model ${DIM}[databricks-claude-sonnet-4-6]${RESET}: ")" ANTHROPIC_SONNET_MODEL
ANTHROPIC_SONNET_MODEL="${ANTHROPIC_SONNET_MODEL:-databricks-claude-sonnet-4-6}"

read -rp "$(echo -e "  ${CYAN}?${RESET} Haiku model ${DIM}[databricks-claude-haiku-4-5]${RESET}: ")" ANTHROPIC_HAIKU_MODEL
ANTHROPIC_HAIKU_MODEL="${ANTHROPIC_HAIKU_MODEL:-databricks-claude-haiku-4-5}"

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
    # Expand ~ if present and resolve to absolute path
    CUSTOM_PATH="${CUSTOM_PATH/#\~/$HOME}"
    mkdir -p "$CUSTOM_PATH"
    SETTINGS_BASE="$(cd "$CUSTOM_PATH" && pwd)"
    ;;
esac

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

PROFILE="__PROFILE__"
HOST="__HOST__"
LIFETIME="__LIFETIME__"
CACHE_FILE="__CACHE_FILE__"

get_cached_token() {
  [ -f "$CACHE_FILE" ] || return 1
  token=$(jq -r '.token // empty' "$CACHE_FILE" 2>/dev/null) || return 1
  expiry=$(jq -r '.expiry_epoch // 0' "$CACHE_FILE" 2>/dev/null) || return 1
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
  oauth_tok=$(databricks auth token --profile "$PROFILE" --output json 2>/dev/null \
    | jq -r '.access_token // empty') || true
  if [ -z "$oauth_tok" ]; then
    echo "FMAPI: OAuth session expired. Run: databricks auth login --host $HOST --profile $PROFILE" >&2
    exit 1
  fi

  # Revoke old FMAPI PATs before creating new one
  databricks tokens list --profile "$PROFILE" --output json 2>/dev/null \
    | jq -r '.[] | select((.comment // "") | startswith("Claude Code FMAPI")) | .token_id' 2>/dev/null \
    | while IFS= read -r tid; do
        [ -n "$tid" ] && databricks tokens delete "$tid" --profile "$PROFILE" 2>/dev/null || true
      done

  # Create new PAT
  pat_json=$(databricks tokens create \
    --lifetime-seconds "$LIFETIME" \
    --comment "Claude Code FMAPI (created $(date '+%Y-%m-%d'))" \
    --profile "$PROFILE" \
    --output json)
  token=$(echo "$pat_json" | jq -r '.token_value // empty')

  if [ -z "$token" ]; then
    echo "FMAPI: Failed to create PAT." >&2
    exit 1
  fi

  # Write cache atomically
  expiry=$(($(date +%s) + LIFETIME))
  tmpfile=$(mktemp "${CACHE_FILE}.XXXXXX")
  _cleanup_tmp="$tmpfile"
  jq -n --arg tok "$token" --argjson exp "$expiry" --argjson lt "$LIFETIME" \
    '{token: $tok, expiry_epoch: $exp, lifetime_seconds: $lt}' > "$tmpfile"
  chmod 600 "$tmpfile"
  mv "$tmpfile" "$CACHE_FILE"
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

# ── Remove legacy shell wrappers ─────────────────────────────────────────────
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [[ -f "$rc" ]] || continue
  while grep -q '# >>> .* wrapper >>>' "$rc" 2>/dev/null; do
    wrapper_cmd=$(grep -m1 '# >>> .* wrapper >>>' "$rc" | sed 's/^# >>> \(.*\) wrapper >>>$/\1/')
    begin_marker="# >>> ${wrapper_cmd} wrapper >>>"
    end_marker="# <<< ${wrapper_cmd} wrapper <<<"
    sed -i '' "/${begin_marker}/,/${end_marker}/d" "$rc"
    info "Removed legacy ${wrapper_cmd} wrapper from ${rc}."
  done
done

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
