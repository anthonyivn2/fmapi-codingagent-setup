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

# ── Help ──────────────────────────────────────────────────────────────────────
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
  echo "Usage: bash setup_fmapi_cc.sh"
  echo "Sets up Claude Code to use Databricks Foundation Model API."
  echo "Requires: brew, jq"
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

select_option "Command name" \
  "fmapi-claude|separate command, default" \
  "claude|override the default claude command" \
  "Custom|enter your own command name"
CMD_CHOICE="$SELECT_RESULT"

case "$CMD_CHOICE" in
  1) CMD_NAME="fmapi-claude" ;;
  2) CMD_NAME="claude" ;;
  3)
    read -rp "$(echo -e "  ${CYAN}?${RESET} Command name: ")" CMD_NAME
    [[ -z "$CMD_NAME" ]] && { error "Command name is required."; exit 1; }
    # Validate: must be a valid shell function name (alphanumeric, hyphens, underscores)
    [[ "$CMD_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || { error "Invalid command name: '$CMD_NAME'. Use letters, numbers, hyphens, and underscores."; exit 1; }
    ;;
esac

select_option "Settings location" \
  "Current directory|./.claude/settings.json" \
  "Home directory|~/.claude/settings.json" \
  "Custom path|enter your own path"
SETTINGS_CHOICE="$SELECT_RESULT"

case "$SETTINGS_CHOICE" in
  1)
    SETTINGS_BASE="$(cd "$(pwd)" && pwd)"
    ;;
  2)
    SETTINGS_BASE="$HOME"
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
  '{
    "ANTHROPIC_MODEL": $model,
    "ANTHROPIC_BASE_URL": $base,
    "ANTHROPIC_AUTH_TOKEN": $token,
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "databricks-claude-opus-4-6",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "databricks-claude-sonnet-4-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "databricks-claude-haiku-4-5",
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
echo -e "  ${DIM}Auth${RESET}       ${BOLD}PAT (${PAT_LIFETIME_LABEL}, expires $(date -r "$PAT_EXPIRY_EPOCH" '+%Y-%m-%d %H:%M %Z'))${RESET}"
echo -e "  ${DIM}Command${RESET}    ${BOLD}${CMD_NAME}${RESET}"
echo -e "  ${DIM}Settings${RESET}   ${BOLD}${SETTINGS_FILE}${RESET}"
echo -e "\n  Run ${CYAN}${BOLD}source ${RC_FILE}${RESET} or open a ${BOLD}new terminal${RESET}, then run ${CYAN}${BOLD}${CMD_NAME}${RESET} to start.\n"
