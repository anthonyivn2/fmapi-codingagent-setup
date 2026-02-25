#!/bin/bash
set -euo pipefail

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

  # ── Discover wrappers in both RC files ───────────────────────────────────
  local rc_files=("$HOME/.zshrc" "$HOME/.bashrc")
  declare -a wrapper_entries=()   # "rc_file|cmd_name|profile|settings_file"
  declare -a found_settings=()

  for rc in "${rc_files[@]}"; do
    [[ -f "$rc" ]] || continue
    # Find all begin markers: # >>> <name> wrapper >>>
    while IFS= read -r marker_line; do
      local cmd_name=""
      cmd_name=$(echo "$marker_line" | sed -n 's/^# >>> \(.*\) wrapper >>>$/\1/p')
      [[ -z "$cmd_name" ]] && continue

      local end_marker="# <<< ${cmd_name} wrapper <<<"

      # Extract profile from the wrapper block
      local profile=""
      profile=$(sed -n "/# >>> ${cmd_name} wrapper >>>/,/${end_marker}/{ s/.*profile=\"\([^\"]*\)\".*/\1/p; }" "$rc" | head -1)

      # Extract settings file path from the wrapper block
      local sf=""
      sf=$(sed -n "/# >>> ${cmd_name} wrapper >>>/,/${end_marker}/{ s/.*local sf=\"\([^\"]*\)\".*/\1/p; }" "$rc" | head -1)

      wrapper_entries+=("${rc}|${cmd_name}|${profile}|${sf}")

      # Collect settings file if it exists
      if [[ -n "$sf" ]]; then
        found_settings+=("$sf")
      fi
    done < <(grep -n '# >>> .* wrapper >>>' "$rc" 2>/dev/null | sed 's/^[0-9]*://')
  done

  # ── Discover settings files ──────────────────────────────────────────────
  # Add well-known locations
  for candidate in "$HOME/.claude/settings.json" "./.claude/settings.json"; do
    found_settings+=("$candidate")
  done

  # Deduplicate by absolute path, keep only files with _fmapi_meta
  declare -a settings_files=()
  for sf in "${found_settings[@]}"; do
    [[ -z "$sf" ]] && continue
    # Expand ~ if present
    sf="${sf/#\~/$HOME}"
    # Resolve to absolute path if file exists
    if [[ -f "$sf" ]]; then
      local abs_path=""
      abs_path=$(cd "$(dirname "$sf")" && echo "$(pwd)/$(basename "$sf")")
      if ! array_contains "$abs_path" ${settings_files[@]+"${settings_files[@]}"}; then
        # Only include if it has _fmapi_meta
        if jq -e '._fmapi_meta' "$abs_path" &>/dev/null; then
          settings_files+=("$abs_path")
        fi
      fi
    fi
  done

  # ── Collect unique profiles ──────────────────────────────────────────────
  declare -a profiles=()
  for entry in "${wrapper_entries[@]}"; do
    local profile=""
    profile=$(echo "$entry" | cut -d'|' -f3)
    if [[ -n "$profile" ]] && ! array_contains "$profile" ${profiles[@]+"${profiles[@]}"}; then
      profiles+=("$profile")
    fi
  done

  # ── Early exit if nothing found ──────────────────────────────────────────
  if [[ ${#wrapper_entries[@]} -eq 0 && ${#settings_files[@]} -eq 0 ]]; then
    info "Nothing to uninstall. No FMAPI wrappers or settings found."
    exit 0
  fi

  # ── Display findings ─────────────────────────────────────────────────────
  echo -e "  ${BOLD}Found the following FMAPI artifacts:${RESET}\n"

  if [[ ${#wrapper_entries[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}Shell wrappers:${RESET}"
    for entry in "${wrapper_entries[@]}"; do
      local rc="" cmd=""
      rc=$(echo "$entry" | cut -d'|' -f1)
      cmd=$(echo "$entry" | cut -d'|' -f2)
      echo -e "    ${BOLD}${cmd}${RESET} in ${DIM}${rc}${RESET}"
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
  select_option "Remove wrappers and clean settings?" \
    "Yes|remove FMAPI artifacts listed above" \
    "No|cancel and exit"
  [[ "$SELECT_RESULT" -ne 1 ]] && { info "Cancelled."; exit 0; }

  echo ""

  # ── Remove wrapper blocks ────────────────────────────────────────────────
  for entry in "${wrapper_entries[@]}"; do
    local rc="" cmd=""
    rc=$(echo "$entry" | cut -d'|' -f1)
    cmd=$(echo "$entry" | cut -d'|' -f2)
    local begin="# >>> ${cmd} wrapper >>>"
    local end="# <<< ${cmd} wrapper <<<"
    if grep -qF "$begin" "$rc" 2>/dev/null; then
      sed -i '' "/$begin/,/$end/d" "$rc"
      success "Removed ${cmd} wrapper from ${rc}."
    fi
  done

  # ── Clean settings files ─────────────────────────────────────────────────
  local fmapi_env_keys='["ANTHROPIC_MODEL","ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_DEFAULT_OPUS_MODEL","ANTHROPIC_DEFAULT_SONNET_MODEL","ANTHROPIC_DEFAULT_HAIKU_MODEL","ANTHROPIC_CUSTOM_HEADERS","CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS"]'

  for sf in "${settings_files[@]}"; do
    local tmpfile=""
    tmpfile=$(mktemp "${sf}.XXXXXX")
    jq --argjson keys "$fmapi_env_keys" '
      .env = ((.env // {}) | to_entries | map(select(.key as $k | $keys | index($k) | not)) | from_entries)
      | del(._fmapi_meta)
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

  # Collect unique RC files that were modified
  declare -a modified_rcs=()
  for entry in "${wrapper_entries[@]}"; do
    local rc=""
    rc=$(echo "$entry" | cut -d'|' -f1)
    if ! array_contains "$rc" ${modified_rcs[@]+"${modified_rcs[@]}"}; then
      modified_rcs+=("$rc")
    fi
  done
  for rc in "${modified_rcs[@]}"; do
    echo -e "  Run ${CYAN}${BOLD}source ${rc}${RESET} or open a ${BOLD}new terminal${RESET} to apply changes."
  done
  echo ""
}

# ── Help ──────────────────────────────────────────────────────────────────────
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
  echo "Usage: bash setup-fmapi-claudecode.sh [--uninstall] [-h|--help]"
  echo ""
  echo "Sets up Claude Code to use Databricks Foundation Model API."
  echo "Installs prerequisites automatically (Homebrew, jq, Claude Code, Databricks CLI)."
  echo ""
  echo "Options:"
  echo "  --uninstall   Remove FMAPI wrappers, settings, and optionally revoke PATs"
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

select_option "Command name" \
  "claude|override the default claude command, default" \
  "fmapi-claude|separate command" \
  "Custom|enter your own command name"
CMD_CHOICE="$SELECT_RESULT"

case "$CMD_CHOICE" in
  1) CMD_NAME="claude" ;;
  2) CMD_NAME="fmapi-claude" ;;
  3)
    read -rp "$(echo -e "  ${CYAN}?${RESET} Command name: ")" CMD_NAME
    [[ -z "$CMD_NAME" ]] && { error "Command name is required."; exit 1; }
    # Validate: must be a valid shell function name (alphanumeric, hyphens, underscores)
    [[ "$CMD_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || { error "Invalid command name: '$CMD_NAME'. Use letters, numbers, hyphens, and underscores."; exit 1; }
    ;;
esac

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
ANTHROPIC_AUTH_TOKEN=$(echo "$PAT_JSON" | jq -r '.token_value // empty')
[[ -z "$ANTHROPIC_AUTH_TOKEN" ]] && { error "Failed to create PAT."; exit 1; }
PAT_EXPIRY_EPOCH=$(( $(date +%s) + PAT_LIFETIME_SECONDS ))
success "PAT created (expires: $(date -r "$PAT_EXPIRY_EPOCH" '+%Y-%m-%d %H:%M %Z'))."

# ── Write .claude/settings.json ──────────────────────────────────────────────
echo -e "\n${BOLD}Writing settings${RESET}"

mkdir -p "$(dirname "$SETTINGS_FILE")"

env_json=$(jq -n \
  --arg model "$ANTHROPIC_MODEL" \
  --arg base  "${DATABRICKS_HOST}/serving-endpoints/anthropic" \
  --arg token "$ANTHROPIC_AUTH_TOKEN" \
  --arg opus "$ANTHROPIC_OPUS_MODEL" \
  --arg sonnet "$ANTHROPIC_SONNET_MODEL" \
  --arg haiku "$ANTHROPIC_HAIKU_MODEL" \
  '{
    "ANTHROPIC_MODEL": $model,
    "ANTHROPIC_BASE_URL": $base,
    "ANTHROPIC_AUTH_TOKEN": $token,
    "ANTHROPIC_DEFAULT_OPUS_MODEL": $opus,
    "ANTHROPIC_DEFAULT_SONNET_MODEL": $sonnet,
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": $haiku,
    "ANTHROPIC_CUSTOM_HEADERS": "x-databricks-use-coding-agent-mode: true",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1"
  }')

meta_json=$(jq -n \
  --arg method "pat" \
  --argjson expiry "$PAT_EXPIRY_EPOCH" \
  --argjson lifetime "$PAT_LIFETIME_SECONDS" \
  '{auth_method: $method, pat_expiry_epoch: $expiry, pat_lifetime_seconds: $lifetime}')

if [[ -f "$SETTINGS_FILE" ]]; then
  tmpfile=$(mktemp "${SETTINGS_FILE}.XXXXXX")
  jq --argjson new_env "$env_json" --argjson meta "$meta_json" \
    '.env = ((.env // {}) * $new_env) | ._fmapi_meta = $meta' \
    "$SETTINGS_FILE" > "$tmpfile"
  chmod 600 "$tmpfile"
  mv "$tmpfile" "$SETTINGS_FILE"
else
  jq -n --argjson env "$env_json" --argjson meta "$meta_json" \
    '{"env": $env, "_fmapi_meta": $meta}' > "$SETTINGS_FILE"
  chmod 600 "$SETTINGS_FILE"
fi
success "Settings written to ${SETTINGS_FILE}."

# ── Add shell wrapper ────────────────────────────────────────────────────────
echo -e "\n${BOLD}Shell wrapper${RESET}"

RC_FILE="$HOME/.zshrc"
[[ "$SHELL" != */zsh ]] && RC_FILE="$HOME/.bashrc"

BEGIN_MARKER="# >>> ${CMD_NAME} wrapper >>>"
END_MARKER="# <<< ${CMD_NAME} wrapper <<<"

# Remove legacy wrapper names if present
for OLD_NAME in "claude_fmapi" "dbx-fmapi-claude"; do
  OLD_MARKER="# >>> ${OLD_NAME} wrapper >>>"
  OLD_END="# <<< ${OLD_NAME} wrapper <<<"
  if grep -qF "$OLD_MARKER" "$RC_FILE" 2>/dev/null; then
    sed -i '' "/$OLD_MARKER/,/$OLD_END/d" "$RC_FILE"
    info "Removed old ${OLD_NAME} wrapper."
  fi
done

# Remove previous fmapi-claude wrapper if the command name changed
if [[ "$CMD_NAME" != "fmapi-claude" ]]; then
  OLD_DBX_MARKER="# >>> fmapi-claude wrapper >>>"
  OLD_DBX_END="# <<< fmapi-claude wrapper <<<"
  if grep -qF "$OLD_DBX_MARKER" "$RC_FILE" 2>/dev/null; then
    sed -i '' "/$OLD_DBX_MARKER/,/$OLD_DBX_END/d" "$RC_FILE"
    info "Removed old fmapi-claude wrapper."
  fi
fi

if grep -qF "$BEGIN_MARKER" "$RC_FILE" 2>/dev/null; then
  OLD_PROFILE=$(sed -n "/$BEGIN_MARKER/,/$END_MARKER/{ s/.*profile=\"\([^\"]*\)\".*/\1/p; }" "$RC_FILE" | head -1)
  if [[ -n "$OLD_PROFILE" && "$OLD_PROFILE" != "$DATABRICKS_PROFILE" ]]; then
    info "Replacing profile ${OLD_PROFILE} → ${DATABRICKS_PROFILE} in ${RC_FILE} ..."
  else
    info "Updating wrapper in ${RC_FILE} ..."
  fi
  sed -i '' "/$BEGIN_MARKER/,/$END_MARKER/d" "$RC_FILE"
else
  info "Adding wrapper to ${RC_FILE} ..."
fi

cat >> "$RC_FILE" << 'WRAPPER'

# >>> CMD_NAME_PLACEHOLDER wrapper >>>
CMD_NAME_PLACEHOLDER() {
  local sf="SETTINGS_FILE_PLACEHOLDER"
  [[ ! -f "$sf" ]] && { command claude "$@"; return; }

  local token host profile="PROFILE_PLACEHOLDER"
  token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN // empty' "$sf")
  host=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$sf")
  host="${host%/serving-endpoints/anthropic}"

  # Check PAT expiry via local clock (no HTTP call)
  local expiry lifetime now
  expiry=$(jq -r '._fmapi_meta.pat_expiry_epoch // 0' "$sf")
  lifetime=$(jq -r '._fmapi_meta.pat_lifetime_seconds // 86400' "$sf")
  now=$(date +%s)

  if [[ -z "$token" ]] || (( now >= expiry )); then
    echo "[CMD_NAME_PLACEHOLDER] PAT expired, creating new one ..."

    # Ensure OAuth session is valid for PAT creation
    local oauth_tok=""
    oauth_tok=$(databricks auth token --profile "$profile" --output json 2>/dev/null | jq -r '.access_token // empty') || true
    if [[ -z "$oauth_tok" ]]; then
      echo "[CMD_NAME_PLACEHOLDER] OAuth login required ..."
      databricks auth login --host "$host" --profile "$profile"
    fi

    # Revoke old FMAPI PATs before creating new one
    databricks tokens list --profile "$profile" --output json 2>/dev/null \
      | jq -r '.[] | select((.comment // "") | startswith("Claude Code FMAPI")) | .token_id' 2>/dev/null \
      | while IFS= read -r tid; do
          [[ -n "$tid" ]] && databricks tokens delete "$tid" --profile "$profile" 2>/dev/null || true
        done

    local pat_json new_token new_expiry
    pat_json=$(databricks tokens create \
      --lifetime-seconds "$lifetime" \
      --comment "Claude Code FMAPI (created $(date '+%Y-%m-%d'))" \
      --profile "$profile" \
      --output json)
    new_token=$(echo "$pat_json" | jq -r '.token_value // empty')

    if [[ -n "$new_token" ]]; then
      new_expiry=$(( $(date +%s) + lifetime ))
      local tmpfile
      tmpfile=$(mktemp "${sf}.XXXXXX")
      jq --arg tok "$new_token" --argjson exp "$new_expiry" \
        '.env.ANTHROPIC_AUTH_TOKEN = $tok | ._fmapi_meta.pat_expiry_epoch = $exp' \
        "$sf" > "$tmpfile" && chmod 600 "$tmpfile" && mv "$tmpfile" "$sf"
      echo "[CMD_NAME_PLACEHOLDER] PAT refreshed (expires: $(date -r "$new_expiry" '+%Y-%m-%d %H:%M %Z'))."
    else
      echo "[CMD_NAME_PLACEHOLDER] Error: could not create PAT." >&2
      return 1
    fi
  fi

  command claude "$@"
}
# <<< CMD_NAME_PLACEHOLDER wrapper <<<
WRAPPER

# Replace placeholders with actual values
sed -i '' "s|CMD_NAME_PLACEHOLDER|${CMD_NAME}|g; s|SETTINGS_FILE_PLACEHOLDER|${SETTINGS_FILE}|g; s|PROFILE_PLACEHOLDER|${DATABRICKS_PROFILE}|g" "$RC_FILE"
success "Wrapper written to ${RC_FILE}."

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}  Setup complete!${RESET}"
echo -e "  ${DIM}Workspace${RESET}  ${BOLD}${DATABRICKS_HOST}${RESET}"
echo -e "  ${DIM}Profile${RESET}    ${BOLD}${DATABRICKS_PROFILE}${RESET}"
echo -e "  ${DIM}Model${RESET}      ${BOLD}${ANTHROPIC_MODEL}${RESET}"
echo -e "  ${DIM}Opus${RESET}       ${BOLD}${ANTHROPIC_OPUS_MODEL}${RESET}"
echo -e "  ${DIM}Sonnet${RESET}     ${BOLD}${ANTHROPIC_SONNET_MODEL}${RESET}"
echo -e "  ${DIM}Haiku${RESET}      ${BOLD}${ANTHROPIC_HAIKU_MODEL}${RESET}"
echo -e "  ${DIM}Auth${RESET}       ${BOLD}PAT (${PAT_LIFETIME_LABEL}, expires $(date -r "$PAT_EXPIRY_EPOCH" '+%Y-%m-%d %H:%M %Z'))${RESET}"
echo -e "  ${DIM}Command${RESET}    ${BOLD}${CMD_NAME}${RESET}"
echo -e "  ${DIM}Settings${RESET}   ${BOLD}${SETTINGS_FILE}${RESET}"
echo -e "\n  Run ${CYAN}${BOLD}source ${RC_FILE}${RESET} or open a ${BOLD}new terminal${RESET}, then run ${CYAN}${BOLD}${CMD_NAME}${RESET} to start.\n"
