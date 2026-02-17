#!/bin/bash
set -euo pipefail

# ── Formatting ────────────────────────────────────────────────────────────────
BOLD='\033[1m' DIM='\033[2m' RED='\033[31m' GREEN='\033[32m'
YELLOW='\033[33m' CYAN='\033[36m' RESET='\033[0m'

info()    { echo -e "  ${CYAN}::${RESET} $1"; }
success() { echo -e "  ${GREEN}${BOLD}ok${RESET} $1"; }
error()   { echo -e "\n  ${RED}${BOLD}!! ERROR${RESET}${RED} $1${RESET}\n" >&2; }

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

read -rp "$(echo -e "  ${CYAN}?${RESET} Model ${DIM}[databricks-claude-opus-4-6]${RESET}: ")" ANTHROPIC_MODEL
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-databricks-claude-opus-4-6}"

echo -e "  ${CYAN}?${RESET} Settings location ${DIM}[1]${RESET}:"
echo -e "    1) Current directory  ${DIM}(./.claude/settings.json)${RESET}"
echo -e "    2) Home directory     ${DIM}(~/.claude/settings.json)${RESET}"
echo -e "    3) Custom path"
read -rp "$(echo -e "  ${CYAN}>${RESET} ")" SETTINGS_CHOICE
SETTINGS_CHOICE="${SETTINGS_CHOICE:-1}"

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
  *)
    error "Invalid choice: $SETTINGS_CHOICE"; exit 1
    ;;
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

get_token() {
  databricks auth token --profile "$DATABRICKS_PROFILE" --output json 2>/dev/null \
    | jq -r '.access_token // empty'
}

ANTHROPIC_AUTH_TOKEN=$(get_token) || true
if [[ -z "$ANTHROPIC_AUTH_TOKEN" ]]; then
  info "Logging in to ${DATABRICKS_HOST} ..."
  databricks auth login --host "$DATABRICKS_HOST" --profile "$DATABRICKS_PROFILE"
  ANTHROPIC_AUTH_TOKEN=$(get_token)
fi

[[ -z "$ANTHROPIC_AUTH_TOKEN" ]] && { error "Failed to get access token."; exit 1; }
success "Authenticated."

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

if [[ -f "$SETTINGS_FILE" ]]; then
  jq --argjson new_env "$env_json" '.env = ((.env // {}) * $new_env)' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
  mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
else
  jq -n --argjson env "$env_json" '{"env": $env}' > "$SETTINGS_FILE"
fi
success "Settings written to ${SETTINGS_FILE}."

# ── Add shell wrapper ────────────────────────────────────────────────────────
echo -e "\n${BOLD}Shell wrapper${RESET}"

RC_FILE="$HOME/.zshrc"
[[ "$SHELL" != */zsh ]] && RC_FILE="$HOME/.bashrc"

BEGIN_MARKER="# >>> dbx-fmapi-claude wrapper >>>"
END_MARKER="# <<< dbx-fmapi-claude wrapper <<<"

# Remove old claude_fmapi wrapper if present
OLD_MARKER="# >>> claude_fmapi wrapper >>>"
OLD_END="# <<< claude_fmapi wrapper <<<"
if grep -qF "$OLD_MARKER" "$RC_FILE" 2>/dev/null; then
  sed -i '' "/$OLD_MARKER/,/$OLD_END/d" "$RC_FILE"
  info "Removed old claude_fmapi wrapper."
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

cat >> "$RC_FILE" << WRAPPER

# >>> dbx-fmapi-claude wrapper >>>
dbx-fmapi-claude() {
  local sf="${SETTINGS_FILE}"
  [[ ! -f "\$sf" ]] && { command claude "\$@"; return; }

  local token host profile="${DATABRICKS_PROFILE}"
  token=\$(jq -r '.env.ANTHROPIC_AUTH_TOKEN // empty' "\$sf")
  host=\$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "\$sf")
  host="\${host%/serving-endpoints/anthropic}"

  # Check if token is still valid
  if [[ -z "\$token" ]] || \\
     [[ "\$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer \$token" "\$host/api/2.0/token/list" 2>/dev/null)" != "200" ]]; then

    echo "[dbx-fmapi-claude] Refreshing token ..."
    local new_token=""
    new_token=\$(databricks auth token --profile "\$profile" --output json 2>/dev/null | jq -r '.access_token // empty') || true

    if [[ -z "\$new_token" ]]; then
      echo "[dbx-fmapi-claude] OAuth login required ..."
      databricks auth login --host "\$host" --profile "\$profile"
      new_token=\$(databricks auth token --profile "\$profile" --output json 2>/dev/null | jq -r '.access_token // empty') || true
    fi

    if [[ -n "\$new_token" ]]; then
      jq --arg tok "\$new_token" '.env.ANTHROPIC_AUTH_TOKEN = \$tok' "\$sf" > "\${sf}.tmp" && mv "\${sf}.tmp" "\$sf"
      echo "[dbx-fmapi-claude] Token refreshed."
    else
      echo "[dbx-fmapi-claude] Error: could not obtain token." >&2
      return 1
    fi
  fi

  command claude "\$@"
}
# <<< dbx-fmapi-claude wrapper <<<
WRAPPER
success "Wrapper written to ${RC_FILE}."

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}  Setup complete!${RESET}"
echo -e "  ${DIM}Workspace${RESET}  ${BOLD}${DATABRICKS_HOST}${RESET}"
echo -e "  ${DIM}Profile${RESET}    ${BOLD}${DATABRICKS_PROFILE}${RESET}"
echo -e "  ${DIM}Model${RESET}      ${BOLD}${ANTHROPIC_MODEL}${RESET}"
echo -e "  ${DIM}Settings${RESET}   ${BOLD}${SETTINGS_FILE}${RESET}"
echo -e "\n  Run ${CYAN}${BOLD}source ${RC_FILE}${RESET} or open a ${BOLD}new terminal${RESET}, then run ${CYAN}${BOLD}dbx-fmapi-claude${RESET} to start.\n"
