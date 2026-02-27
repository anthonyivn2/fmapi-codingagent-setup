#!/bin/bash
# lib/setup.sh — Setup workflow functions
# Sourced by setup-fmapi-claudecode.sh; do not run directly.

# ── Setup functions ───────────────────────────────────────────────────────────

gather_config() {
  # Initialize CFG_* defaults (discover_config sets these, but jq may not be available yet)
  CFG_FOUND=false CFG_HOST="" CFG_PROFILE=""
  CFG_MODEL="" CFG_OPUS="" CFG_SONNET="" CFG_HAIKU=""
  CFG_TTL=""
  CFG_SETTINGS_FILE="" CFG_HELPER_FILE=""

  # Discover existing config for defaults
  if command -v jq &>/dev/null; then
    discover_config
  fi

  debug "discover_config: CFG_FOUND=${CFG_FOUND} CFG_HOST=${CFG_HOST} CFG_PROFILE=${CFG_PROFILE}"

  # Resolve defaults: CLI flag > config file > discovered config > hardcoded default
  _default() { echo "${1:-${2:-${3:-${4:-}}}}"; }

  local default_host default_profile default_model default_opus default_sonnet default_haiku default_ttl
  default_host=$(_default "$CLI_HOST" "$FILE_HOST" "$CFG_HOST" "")
  default_profile=$(_default "$CLI_PROFILE" "$FILE_PROFILE" "$CFG_PROFILE" "fmapi-claudecode-profile")
  default_model=$(_default "$CLI_MODEL" "$FILE_MODEL" "$CFG_MODEL" "databricks-claude-opus-4-6")
  default_opus=$(_default "$CLI_OPUS" "$FILE_OPUS" "$CFG_OPUS" "databricks-claude-opus-4-6")
  default_sonnet=$(_default "$CLI_SONNET" "$FILE_SONNET" "$CFG_SONNET" "databricks-claude-sonnet-4-6")
  default_haiku=$(_default "$CLI_HAIKU" "$FILE_HAIKU" "$CFG_HAIKU" "databricks-claude-haiku-4-5")
  default_ttl=$(_default "$CLI_TTL" "$FILE_TTL" "$CFG_TTL" "30")

  # ── Workspace URL ─────────────────────────────────────────────────────────
  prompt_value DATABRICKS_HOST "Databricks workspace URL" "$CLI_HOST" "$default_host"
  [[ -z "$DATABRICKS_HOST" ]] && { error "Workspace URL is required."; exit 1; }
  DATABRICKS_HOST="${DATABRICKS_HOST%/}"
  [[ "$DATABRICKS_HOST" != https://* ]] && { error "Workspace URL must start with https://"; exit 1; }

  # ── CLI profile ───────────────────────────────────────────────────────────
  prompt_value DATABRICKS_PROFILE "Databricks CLI profile name" "$CLI_PROFILE" "$default_profile"
  [[ -z "$DATABRICKS_PROFILE" ]] && { error "Profile name is required."; exit 1; }
  [[ "$DATABRICKS_PROFILE" =~ ^[a-zA-Z0-9_-]+$ ]] || { error "Invalid profile name: '$DATABRICKS_PROFILE'. Use letters, numbers, hyphens, and underscores."; exit 1; }

  # ── Models ────────────────────────────────────────────────────────────────
  prompt_value ANTHROPIC_MODEL "Model" "$CLI_MODEL" "$default_model"
  prompt_value ANTHROPIC_OPUS_MODEL "Opus model" "$CLI_OPUS" "$default_opus"
  prompt_value ANTHROPIC_SONNET_MODEL "Sonnet model" "$CLI_SONNET" "$default_sonnet"
  prompt_value ANTHROPIC_HAIKU_MODEL "Haiku model" "$CLI_HAIKU" "$default_haiku"

  # ── Token refresh interval ───────────────────────────────────────────────
  prompt_value FMAPI_TTL_MINUTES "Token refresh interval (minutes)" "$CLI_TTL" "$default_ttl"
  if ! [[ "$FMAPI_TTL_MINUTES" =~ ^[0-9]+$ ]] || [[ "$FMAPI_TTL_MINUTES" -le 0 ]]; then
    error "Token refresh interval must be a positive integer (minutes)."
    exit 1
  fi
  if [[ "$FMAPI_TTL_MINUTES" -gt 60 ]]; then
    error "Token refresh interval cannot exceed 60 minutes. OAuth tokens expire after 1 hour."
    exit 1
  fi
  FMAPI_TTL_MS=$(( FMAPI_TTL_MINUTES * 60000 ))

  # ── Settings location ────────────────────────────────────────────────────
  local resolved_settings_location="${CLI_SETTINGS_LOCATION:-$FILE_SETTINGS_LOCATION}"
  if [[ -n "$resolved_settings_location" ]]; then
    case "$resolved_settings_location" in
      home) SETTINGS_BASE="$HOME" ;;
      cwd)  SETTINGS_BASE="$(cd "$(pwd)" && pwd)" ;;
      *)
        resolved_settings_location="${resolved_settings_location/#\~/$HOME}"
        mkdir -p "$resolved_settings_location"
        SETTINGS_BASE="$(cd "$resolved_settings_location" && pwd)"
        ;;
    esac
  elif [[ "$NON_INTERACTIVE" == true ]]; then
    SETTINGS_BASE="$HOME"
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

  SETTINGS_FILE="${SETTINGS_BASE}/.claude/settings.json"
  HELPER_FILE="${SETTINGS_BASE}/.claude/fmapi-key-helper.sh"

  debug "gather_config: host=${DATABRICKS_HOST} profile=${DATABRICKS_PROFILE} model=${ANTHROPIC_MODEL}"
  debug "gather_config: settings=${SETTINGS_FILE} helper=${HELPER_FILE}"
}

install_dependencies() {
  [[ "$VERBOSITY" -ge 1 ]] && echo -e "\n${BOLD}Installing dependencies${RESET}"

  case "$_OS_TYPE" in
    Darwin)
      # ── macOS: use Homebrew ──────────────────────────────────────────────
      if command -v brew &>/dev/null; then
        success "Homebrew already installed."
      else
        info "Installing Homebrew ..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ -x /opt/homebrew/bin/brew ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
          eval "$(/usr/local/bin/brew shellenv)"
        fi
        success "Homebrew installed."
      fi

      if command -v jq &>/dev/null; then
        success "jq already installed."
      else
        info "Installing jq ..."
        brew install jq
        success "jq installed."
      fi

      if command -v databricks &>/dev/null; then
        success "Databricks CLI already installed."
      else
        info "Installing Databricks CLI ..."
        brew tap databricks/tap && brew install databricks
        success "Databricks CLI installed."
      fi
      ;;
    Linux)
      # ── Linux: use system package manager + curl installers ──────────────
      if command -v jq &>/dev/null; then
        success "jq already installed."
      else
        info "Installing jq ..."
        if command -v apt-get &>/dev/null; then
          sudo apt-get update -qq && sudo apt-get install -y jq
        elif command -v yum &>/dev/null; then
          sudo yum install -y jq
        else
          error "Cannot install jq: no supported package manager (apt-get or yum) found."
          exit 1
        fi
        success "jq installed."
      fi

      if command -v databricks &>/dev/null; then
        success "Databricks CLI already installed."
      else
        info "Installing Databricks CLI ..."
        curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
        success "Databricks CLI installed."
      fi
      ;;
    *)
      error "Unsupported OS: ${_OS_TYPE}. This script supports macOS (Darwin) and Linux."
      exit 1
      ;;
  esac

  # Claude Code — cross-platform installer
  if command -v claude &>/dev/null; then
    success "Claude Code already installed."
  else
    info "Installing Claude Code ..."
    curl -fsSL https://claude.ai/install.sh | bash
    success "Claude Code installed."
  fi
}

authenticate() {
  [[ "$VERBOSITY" -ge 1 ]] && echo -e "\n${BOLD}Authenticating${RESET}"

  get_oauth_token() {
    databricks auth token --profile "$DATABRICKS_PROFILE" --output json 2>/dev/null \
      | jq -r '.access_token // empty'
  }

  OAUTH_TOKEN=$(get_oauth_token) || true
  debug "authenticate: existing token=${OAUTH_TOKEN:+present}${OAUTH_TOKEN:-missing}"
  if [[ -z "$OAUTH_TOKEN" ]]; then
    if _is_headless; then
      echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Headless SSH session detected. Browser-based OAuth may not work."
    fi
    info "Logging in to ${DATABRICKS_HOST} ..."
    databricks auth login --host "$DATABRICKS_HOST" --profile "$DATABRICKS_PROFILE"
    OAUTH_TOKEN=$(get_oauth_token)
  fi

  [[ -z "$OAUTH_TOKEN" ]] && { error "Failed to get OAuth access token."; exit 1; }
  success "OAuth session established."

  # Clean up any legacy FMAPI PATs from prior installations
  OLD_PAT_IDS=$(databricks tokens list --profile "$DATABRICKS_PROFILE" --output json 2>/dev/null \
    | jq -r '.[] | select((.comment // "") | startswith("Claude Code FMAPI")) | .token_id' 2>/dev/null) || true
  if [[ -n "$OLD_PAT_IDS" ]]; then
    info "Cleaning up legacy FMAPI PATs ..."
    while IFS= read -r tid; do
      [[ -n "$tid" ]] && databricks tokens delete "$tid" --profile "$DATABRICKS_PROFILE" 2>/dev/null || true
    done <<< "$OLD_PAT_IDS"
    success "Legacy PATs revoked."
  fi

  # Clean up legacy cache file if present
  LEGACY_CACHE="${SETTINGS_BASE}/.claude/.fmapi-pat-cache"
  if [[ -f "$LEGACY_CACHE" ]]; then
    rm -f "$LEGACY_CACHE"
    success "Removed legacy PAT cache."
  fi
}

write_settings() {
  [[ "$VERBOSITY" -ge 1 ]] && echo -e "\n${BOLD}Writing settings${RESET}"

  mkdir -p "$(dirname "$SETTINGS_FILE")"

  TTL_MS="$FMAPI_TTL_MS"

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
  debug "write_settings: wrote ${SETTINGS_FILE} (TTL=${FMAPI_TTL_MS}ms)"
  success "Settings written to ${SETTINGS_FILE}."
}

ensure_onboarding() {
  local claude_json="$HOME/.claude.json"

  # Check if hasCompletedOnboarding is already true
  if [[ -f "$claude_json" ]]; then
    local current=""
    current=$(jq -r '.hasCompletedOnboarding // empty' "$claude_json" 2>/dev/null) || true
    if [[ "$current" == "true" ]]; then
      debug "ensure_onboarding: already set in ${claude_json}"
      return 0
    fi
  fi

  [[ "$VERBOSITY" -ge 1 ]] && echo -e "\n${BOLD}Onboarding flag${RESET}"

  if [[ -f "$claude_json" ]]; then
    local tmpfile=""
    tmpfile=$(mktemp "${claude_json}.XXXXXX")
    _CLEANUP_FILES+=("$tmpfile")
    jq '.hasCompletedOnboarding = true' "$claude_json" > "$tmpfile"
    chmod 600 "$tmpfile"
    mv "$tmpfile" "$claude_json"
  else
    echo '{"hasCompletedOnboarding":true}' | jq '.' > "$claude_json"
    chmod 600 "$claude_json"
  fi
  debug "ensure_onboarding: set hasCompletedOnboarding=true in ${claude_json}"
  success "Onboarding flag set in ${claude_json}."
}

write_helper() {
  [[ "$VERBOSITY" -ge 1 ]] && echo -e "\n${BOLD}API key helper${RESET}"

  cat > "$HELPER_FILE" << 'HELPER_SCRIPT'
#!/bin/sh
set -eu

FMAPI_PROFILE="__PROFILE__"
FMAPI_HOST="__HOST__"

# Verify required commands exist
if ! command -v databricks >/dev/null 2>&1; then
  echo "FMAPI: databricks CLI not found. Install it and ensure it is on your PATH." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FMAPI: jq not found. Install it and ensure it is on your PATH." >&2
  exit 1
fi

# Get OAuth access token (databricks CLI auto-refreshes using refresh token)
_fetch_token() {
  databricks auth token --profile "$FMAPI_PROFILE" --output json 2>/dev/null \
    | jq -r '.access_token // empty'
}

token=$(_fetch_token) || true

# Retry once after a short delay for transient failures (network blip, CLI lock)
if [ -z "$token" ]; then
  echo "FMAPI: Token fetch failed for profile '$FMAPI_PROFILE', retrying ..." >&2
  sleep 2
  token=$(_fetch_token) || true
fi

if [ -n "$token" ]; then
  echo "$token"
  exit 0
fi

# Detect headless environments (SSH without display forwarding)
_is_headless() {
  [ -n "${SSH_CONNECTION:-}" ] && [ -z "${DISPLAY:-}" ] && return 0
  [ -n "${SSH_TTY:-}" ] && [ -z "${DISPLAY:-}" ] && return 0
  [ ! -e /dev/tty ] && return 0
  return 1
}

# Refresh token likely expired — attempt browser-based re-authentication
if _is_headless; then
  echo "FMAPI: OAuth session expired in a headless environment." >&2
  echo "FMAPI: Re-authenticate from a machine with a browser:" >&2
  echo "FMAPI:   databricks auth login --host $FMAPI_HOST --profile $FMAPI_PROFILE" >&2
  exit 1
fi

if [ -e /dev/tty ]; then
  _out="/dev/tty"
else
  _out="/dev/stderr"
fi

echo "FMAPI: OAuth session expired — attempting re-authentication ..." > "$_out"

# Use timeout if available (standard on Linux, may not exist on macOS)
_reauth_cmd="databricks auth login --host $FMAPI_HOST --profile $FMAPI_PROFILE"
if command -v timeout >/dev/null 2>&1; then
  _reauth_cmd="timeout 30 $_reauth_cmd"
fi

if eval "$_reauth_cmd" > "$_out" 2>&1; then
  token=$(_fetch_token) || true
  if [ -n "$token" ]; then
    echo "FMAPI: Re-authentication successful." > "$_out"
    echo "$token"
    exit 0
  fi
fi

echo "FMAPI: Re-authentication failed. Run one of the following:" >&2
echo "FMAPI:   bash __SETUP_SCRIPT__ --reauth" >&2
echo "FMAPI:   databricks auth login --host $FMAPI_HOST --profile $FMAPI_PROFILE" >&2
exit 1
HELPER_SCRIPT

  local setup_script="${SCRIPT_DIR}/setup-fmapi-claudecode.sh"

  helper_tmp=$(mktemp "${HELPER_FILE}.XXXXXX")
  _CLEANUP_FILES+=("$helper_tmp")
  sed "s|__PROFILE__|${DATABRICKS_PROFILE}|g; s|__HOST__|${DATABRICKS_HOST}|g; s|__SETUP_SCRIPT__|${setup_script}|g" "$HELPER_FILE" > "$helper_tmp"
  mv "$helper_tmp" "$HELPER_FILE"
  chmod 700 "$HELPER_FILE"
  debug "write_helper: wrote ${HELPER_FILE} (profile=${DATABRICKS_PROFILE}, host=${DATABRICKS_HOST})"
  success "Helper script written to ${HELPER_FILE}."
}

register_plugin() {
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
      success "Plugin registered (skills: /fmapi-codingagent-status, /fmapi-codingagent-reauth, /fmapi-codingagent-setup, /fmapi-codingagent-doctor, /fmapi-codingagent-list-models, /fmapi-codingagent-validate-models)."
    fi
  fi
}

run_smoke_test() {
  [[ "$VERBOSITY" -ge 1 ]] && echo -e "\n${BOLD}Verifying setup${RESET}"

  local warnings=0

  # 1. Helper script executes and returns a token
  if [[ -x "$HELPER_FILE" ]]; then
    local helper_token=""
    helper_token=$("$HELPER_FILE" 2>/dev/null) || true
    if [[ -n "$helper_token" ]]; then
      success "Helper script returns a valid token."
    else
      echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Helper script did not return a token."
      (( warnings++ )) || true
    fi
  else
    echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Helper script is not executable: ${HELPER_FILE}"
    (( warnings++ )) || true
  fi

  # 2. Workspace reachable via serving-endpoints API
  local oauth_tok=""
  oauth_tok=$(databricks auth token --profile "$DATABRICKS_PROFILE" --output json 2>/dev/null \
    | jq -r '.access_token // empty') || true
  if [[ -n "$oauth_tok" ]]; then
    local http_code=""
    http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
      -H "Authorization: Bearer ${oauth_tok}" \
      "${DATABRICKS_HOST}/api/2.0/serving-endpoints" 2>/dev/null) || true
    if [[ "$http_code" == "200" ]]; then
      success "Workspace reachable (${DATABRICKS_HOST})."
    elif [[ -n "$http_code" && "$http_code" != "000" ]]; then
      echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Workspace returned HTTP ${http_code}."
      (( warnings++ )) || true
    else
      echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Cannot reach workspace at ${DATABRICKS_HOST}."
      (( warnings++ )) || true
    fi

    # 3. Configured models exist and are ready
    # Temporarily set CFG_ vars so _validate_models_report can work
    local CFG_MODEL="$ANTHROPIC_MODEL"
    local CFG_OPUS="$ANTHROPIC_OPUS_MODEL"
    local CFG_SONNET="$ANTHROPIC_SONNET_MODEL"
    local CFG_HAIKU="$ANTHROPIC_HAIKU_MODEL"
    local CFG_PROFILE="$DATABRICKS_PROFILE"
    if _fetch_endpoints "$DATABRICKS_PROFILE"; then
      _validate_models_report
      if [[ "$_VALIDATE_ALL_PASS" != true ]]; then
        (( warnings++ )) || true
      fi
    else
      echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Could not fetch serving endpoints for model validation."
      (( warnings++ )) || true
    fi
  else
    echo -e "  ${YELLOW}${BOLD}WARN${RESET}  No OAuth token available — skipping connectivity and model checks."
    (( warnings++ )) || true
  fi

  if (( warnings > 0 )); then
    echo -e "\n  ${YELLOW}Setup succeeded with warnings${RESET} — run ${CYAN}--doctor${RESET} for details."
  fi
}

print_summary() {
  [[ "$VERBOSITY" -lt 1 ]] && return 0
  echo -e "\n${GREEN}${BOLD}  Setup complete!${RESET}"
  echo -e "  ${DIM}Workspace${RESET}  ${BOLD}${DATABRICKS_HOST}${RESET}"
  echo -e "  ${DIM}Profile${RESET}    ${BOLD}${DATABRICKS_PROFILE}${RESET}"
  echo -e "  ${DIM}Model${RESET}      ${BOLD}${ANTHROPIC_MODEL}${RESET}"
  echo -e "  ${DIM}Opus${RESET}       ${BOLD}${ANTHROPIC_OPUS_MODEL}${RESET}"
  echo -e "  ${DIM}Sonnet${RESET}     ${BOLD}${ANTHROPIC_SONNET_MODEL}${RESET}"
  echo -e "  ${DIM}Haiku${RESET}      ${BOLD}${ANTHROPIC_HAIKU_MODEL}${RESET}"
  echo -e "  ${DIM}Auth${RESET}       ${BOLD}OAuth (auto-refresh, ${FMAPI_TTL_MINUTES}m check interval)${RESET}"
  echo -e "  ${DIM}Helper${RESET}     ${BOLD}${HELPER_FILE}${RESET}"
  echo -e "  ${DIM}Settings${RESET}   ${BOLD}${SETTINGS_FILE}${RESET}"
  echo -e "\n  Run ${CYAN}${BOLD}claude${RESET} to start.\n"
}

print_dry_run_plan() {
  echo -e "\n${BOLD}  Claude Code x Databricks FMAPI — Dry Run${RESET}\n"
  echo -e "  The following actions ${BOLD}would${RESET} be performed:\n"

  # Dependencies
  echo -e "  ${BOLD}Dependencies${RESET}"
  for dep_name in jq databricks claude; do
    if command -v "$dep_name" &>/dev/null; then
      echo -e "  ${GREEN}${BOLD}ok${RESET}  ${dep_name} already installed"
    else
      echo -e "  ${CYAN}::${RESET}  ${dep_name} would be installed"
    fi
  done
  echo ""

  # Authentication
  echo -e "  ${BOLD}Authentication${RESET}"
  echo -e "  ${CYAN}::${RESET}  OAuth login target: ${BOLD}${DATABRICKS_HOST}${RESET}"
  echo -e "  ${CYAN}::${RESET}  CLI profile: ${BOLD}${DATABRICKS_PROFILE}${RESET}"
  echo ""

  # Settings
  echo -e "  ${BOLD}Settings${RESET}"
  echo -e "  ${CYAN}::${RESET}  Settings file: ${BOLD}${SETTINGS_FILE}${RESET}"
  if [[ -f "$SETTINGS_FILE" ]]; then
    echo -e "       ${DIM}(exists — FMAPI keys would be merged)${RESET}"
  else
    echo -e "       ${DIM}(would be created)${RESET}"
  fi
  echo -e "  ${CYAN}::${RESET}  Env vars that would be set:"
  echo -e "       ANTHROPIC_MODEL=${BOLD}${ANTHROPIC_MODEL}${RESET}"
  echo -e "       ANTHROPIC_BASE_URL=${BOLD}${DATABRICKS_HOST}/serving-endpoints/anthropic${RESET}"
  echo -e "       ANTHROPIC_DEFAULT_OPUS_MODEL=${BOLD}${ANTHROPIC_OPUS_MODEL}${RESET}"
  echo -e "       ANTHROPIC_DEFAULT_SONNET_MODEL=${BOLD}${ANTHROPIC_SONNET_MODEL}${RESET}"
  echo -e "       ANTHROPIC_DEFAULT_HAIKU_MODEL=${BOLD}${ANTHROPIC_HAIKU_MODEL}${RESET}"
  echo -e "       CLAUDE_CODE_API_KEY_HELPER_TTL_MS=${BOLD}${FMAPI_TTL_MS}${RESET}"
  echo ""

  # Onboarding
  echo -e "  ${BOLD}Onboarding${RESET}"
  local claude_json="$HOME/.claude.json"
  local onboarding_done=false
  if [[ -f "$claude_json" ]]; then
    local ob_val=""
    ob_val=$(jq -r '.hasCompletedOnboarding // empty' "$claude_json" 2>/dev/null) || true
    [[ "$ob_val" == "true" ]] && onboarding_done=true
  fi
  if [[ "$onboarding_done" == true ]]; then
    echo -e "  ${GREEN}${BOLD}ok${RESET}  hasCompletedOnboarding already set in ${DIM}${claude_json}${RESET}"
  else
    echo -e "  ${CYAN}::${RESET}  Would set hasCompletedOnboarding=true in ${DIM}${claude_json}${RESET}"
  fi
  echo ""

  # Helper
  echo -e "  ${BOLD}Helper script${RESET}"
  echo -e "  ${CYAN}::${RESET}  Path: ${BOLD}${HELPER_FILE}${RESET}"
  if [[ -f "$HELPER_FILE" ]]; then
    echo -e "       ${DIM}(exists — would be overwritten)${RESET}"
  else
    echo -e "       ${DIM}(would be created)${RESET}"
  fi
  echo ""

  # Plugin
  echo -e "  ${BOLD}Plugin registration${RESET}"
  local plugins_file="$HOME/.claude/plugins/installed_plugins.json"
  if [[ -f "$plugins_file" ]]; then
    local existing_path=""
    existing_path=$(jq -r '.["fmapi-codingagent"].installPath // empty' "$plugins_file" 2>/dev/null) || true
    if [[ "$existing_path" == "$SCRIPT_DIR" ]]; then
      echo -e "  ${GREEN}${BOLD}ok${RESET}  Already registered"
    else
      echo -e "  ${CYAN}::${RESET}  Would register plugin at ${BOLD}${SCRIPT_DIR}${RESET}"
    fi
  else
    echo -e "  ${CYAN}::${RESET}  Would register plugin at ${BOLD}${SCRIPT_DIR}${RESET}"
  fi
  echo -e "\n  ${DIM}No changes were made. Remove --dry-run to run setup.${RESET}\n"
}

do_setup() {
  echo -e "\n${BOLD}  Claude Code x Databricks FMAPI Setup${RESET}\n"
  gather_config

  if [[ "$DRY_RUN" == true ]]; then
    print_dry_run_plan
    exit 0
  fi

  install_dependencies
  authenticate
  write_settings
  ensure_onboarding
  write_helper
  register_plugin
  run_smoke_test
  print_summary
}
