#!/bin/bash
# lib/setup.sh — Setup workflow functions
# Sourced by setup-fmapi-claudecode.sh; do not run directly.

# ── Setup functions ───────────────────────────────────────────────────────────

gather_config_pre_auth() {
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

  local default_host default_profile default_ttl
  default_host=$(_default "$CLI_HOST" "$FILE_HOST" "$CFG_HOST" "")
  default_profile=$(_default "$CLI_PROFILE" "$FILE_PROFILE" "$CFG_PROFILE" "fmapi-claudecode-profile")
  default_ttl=$(_default "$CLI_TTL" "$FILE_TTL" "$CFG_TTL" "60")

  # Store model defaults as globals for gather_config_models()
  _DEFAULT_MODEL=$(_default "$CLI_MODEL" "$FILE_MODEL" "$CFG_MODEL" "databricks-claude-opus-4-6")
  _DEFAULT_OPUS=$(_default "$CLI_OPUS" "$FILE_OPUS" "$CFG_OPUS" "databricks-claude-opus-4-6")
  _DEFAULT_SONNET=$(_default "$CLI_SONNET" "$FILE_SONNET" "$CFG_SONNET" "databricks-claude-sonnet-4-6")
  _DEFAULT_HAIKU=$(_default "$CLI_HAIKU" "$FILE_HAIKU" "$CFG_HAIKU" "databricks-claude-haiku-4-5")

  # ── Workspace URL ─────────────────────────────────────────────────────────
  prompt_value DATABRICKS_HOST "Databricks workspace URL" "$CLI_HOST" "$default_host"
  if [[ -z "$DATABRICKS_HOST" ]]; then
    error "Workspace URL is required."
    exit 1
  fi
  DATABRICKS_HOST="${DATABRICKS_HOST%/}"
  if [[ "$DATABRICKS_HOST" != https://* ]]; then
    error "Workspace URL must start with https://"
    exit 1
  fi

  # ── API routing mode (AI Gateway v2) ────────────────────────────────────
  local default_ai_gateway
  default_ai_gateway=$(_default "$CLI_AI_GATEWAY" "$FILE_AI_GATEWAY" "$CFG_AI_GATEWAY" "false")

  if [[ "$NON_INTERACTIVE" == true ]]; then
    AI_GATEWAY_ENABLED="$default_ai_gateway"
  else
    select_option "API routing mode" \
      "Serving Endpoints|default" \
      "AI Gateway v2 (beta)|requires account preview enablement"
    if [[ "$SELECT_RESULT" -eq 2 ]]; then
      AI_GATEWAY_ENABLED="true"
      echo -e "  ${YELLOW}${BOLD}NOTE${RESET}  AI Gateway v2 is a ${BOLD}Beta${RESET} feature (${DIM}https://docs.databricks.com/aws/en/release-notes/release-types${RESET})."
      echo -e "        Account admins must enable it from the account console Previews page."
      echo -e "        ${DIM}https://docs.databricks.com/aws/en/admin/workspace-settings/manage-previews${RESET}"
    else
      AI_GATEWAY_ENABLED="false"
    fi
  fi

  # Store pending workspace ID for post-auth resolution
  _PENDING_WORKSPACE_ID=$(_default "$CLI_WORKSPACE_ID" "$FILE_WORKSPACE_ID" "$CFG_WORKSPACE_ID" "")

  # ── CLI profile ───────────────────────────────────────────────────────────
  prompt_value DATABRICKS_PROFILE "Databricks CLI profile name" "$CLI_PROFILE" "$default_profile"
  if [[ -z "$DATABRICKS_PROFILE" ]]; then
    error "Profile name is required."
    exit 1
  fi
  if [[ ! "$DATABRICKS_PROFILE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Invalid profile name: '$DATABRICKS_PROFILE'. Use letters, numbers, hyphens, and underscores."
    exit 1
  fi

  # ── Token refresh interval ───────────────────────────────────────────────
  prompt_value FMAPI_TTL_MINUTES "Token refresh interval in minutes (60 recommended)" "$CLI_TTL" "$default_ttl"
  if ! [[ "$FMAPI_TTL_MINUTES" =~ ^[0-9]+$ ]] || [[ "$FMAPI_TTL_MINUTES" -le 0 ]]; then
    error "Token refresh interval must be a positive integer (minutes)."
    exit 1
  fi
  if [[ "$FMAPI_TTL_MINUTES" -gt 60 ]]; then
    error "Token refresh interval cannot exceed 60 minutes. OAuth tokens expire after 1 hour."
    exit 1
  fi
  if [[ "$FMAPI_TTL_MINUTES" -lt 15 ]]; then
    warn "Token refresh interval under 15 minutes may cause failures during long-running subagent calls."
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
        _validate_settings_path "$resolved_settings_location"
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
        if [[ -z "$CUSTOM_PATH" ]]; then
          error "Custom path is required."
          exit 1
        fi
        CUSTOM_PATH="${CUSTOM_PATH/#\~/$HOME}"
        _validate_settings_path "$CUSTOM_PATH"
        mkdir -p "$CUSTOM_PATH"
        SETTINGS_BASE="$(cd "$CUSTOM_PATH" && pwd)"
        ;;
    esac
  fi

  SETTINGS_FILE="${SETTINGS_BASE}/.claude/settings.json"
  HELPER_FILE="${SETTINGS_BASE}/.claude/fmapi-key-helper.sh"

  debug "gather_config_pre_auth: host=${DATABRICKS_HOST} profile=${DATABRICKS_PROFILE}"
  debug "gather_config_pre_auth: settings=${SETTINGS_FILE} helper=${HELPER_FILE}"
}

gather_config_models() {
  prompt_value ANTHROPIC_MODEL "Model" "$CLI_MODEL" "$_DEFAULT_MODEL"
  prompt_value ANTHROPIC_OPUS_MODEL "Opus model" "$CLI_OPUS" "$_DEFAULT_OPUS"
  prompt_value ANTHROPIC_SONNET_MODEL "Sonnet model" "$CLI_SONNET" "$_DEFAULT_SONNET"
  prompt_value ANTHROPIC_HAIKU_MODEL "Haiku model" "$CLI_HAIKU" "$_DEFAULT_HAIKU"

  debug "gather_config_models: model=${ANTHROPIC_MODEL} opus=${ANTHROPIC_OPUS_MODEL} sonnet=${ANTHROPIC_SONNET_MODEL} haiku=${ANTHROPIC_HAIKU_MODEL}"
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
          export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
        elif [[ -x /usr/local/bin/brew ]]; then
          export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
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

  local OAUTH_TOKEN=""
  OAUTH_TOKEN=$(_get_oauth_token "$DATABRICKS_PROFILE") || true
  debug "authenticate: existing token=${OAUTH_TOKEN:+present}${OAUTH_TOKEN:-missing}"
  if [[ -z "$OAUTH_TOKEN" ]]; then
    if _is_headless; then
      echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Headless SSH session detected. Browser-based OAuth may not work."
    fi
    if [[ "$_IS_WSL" == true ]]; then
      if ! command -v wslview &>/dev/null && ! command -v xdg-open &>/dev/null; then
        warn "WSL detected but no browser opener found."
        info "If the browser does not open, install wslu: ${CYAN}sudo apt-get install -y wslu${RESET}"
      fi
    fi
    info "Logging in to ${DATABRICKS_HOST} ..."
    databricks auth login --host "$DATABRICKS_HOST" --profile "$DATABRICKS_PROFILE"
    OAUTH_TOKEN=$(_get_oauth_token "$DATABRICKS_PROFILE")
  fi

  if [[ -z "$OAUTH_TOKEN" ]]; then
    error "Failed to get OAuth access token."
    exit 1
  fi
  success "OAuth session established."

  # Clean up any legacy FMAPI PATs from prior installations
  local OLD_PAT_IDS=""
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
  local LEGACY_CACHE="${SETTINGS_BASE}/.claude/.fmapi-pat-cache"
  if [[ -f "$LEGACY_CACHE" ]]; then
    rm -f "$LEGACY_CACHE"
    success "Removed legacy PAT cache."
  fi
}

resolve_workspace_id() {
  if [[ "${AI_GATEWAY_ENABLED:-false}" != "true" ]]; then
    WORKSPACE_ID=""
    return 0
  fi

  [[ "$VERBOSITY" -ge 1 ]] && echo -e "\n${BOLD}Resolving workspace ID${RESET}"

  if [[ -n "${_PENDING_WORKSPACE_ID:-}" ]]; then
    WORKSPACE_ID="$_PENDING_WORKSPACE_ID"
    success "Using workspace ID: ${WORKSPACE_ID}"
    return 0
  fi

  # Auto-detect from API response header
  info "Detecting workspace ID from ${DATABRICKS_HOST} ..."
  local detected_id=""
  detected_id=$(_detect_workspace_id "$DATABRICKS_PROFILE" "$DATABRICKS_HOST") || true

  if [[ -n "$detected_id" ]]; then
    WORKSPACE_ID="$detected_id"
    success "Detected workspace ID: ${WORKSPACE_ID}"
    return 0
  fi

  # Auto-detection failed
  if [[ "$NON_INTERACTIVE" == true ]]; then
    error "Could not auto-detect workspace ID. Use --workspace-id to provide it manually."
    exit 1
  fi

  # Interactive fallback: prompt the user
  echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Could not auto-detect workspace ID."
  read -rp "$(echo -e "  ${CYAN}?${RESET} Databricks workspace ID: ")" WORKSPACE_ID
  if [[ -z "$WORKSPACE_ID" ]]; then
    error "Workspace ID is required for AI Gateway v2."
    exit 1
  fi
  if ! [[ "$WORKSPACE_ID" =~ ^[0-9]+$ ]]; then
    error "Workspace ID must be numeric. Got: $WORKSPACE_ID"
    exit 1
  fi
}

write_settings() {
  [[ "$VERBOSITY" -ge 1 ]] && echo -e "\n${BOLD}Writing settings${RESET}"

  mkdir -p "$(dirname "$SETTINGS_FILE")"

  TTL_MS="$FMAPI_TTL_MS"

  local base_url=""
  base_url=$(_build_base_url "$DATABRICKS_HOST" "${AI_GATEWAY_ENABLED:-false}" "${WORKSPACE_ID:-}")

  local env_json=""
  env_json=$(jq -n \
    --arg model "$ANTHROPIC_MODEL" \
    --arg base  "$base_url" \
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
    local tmpfile=""
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

  local template="${SCRIPT_DIR}/templates/fmapi-key-helper.sh.template"
  local setup_script="${SCRIPT_DIR}/setup-fmapi-claudecode.sh"

  if [[ ! -f "$template" ]]; then
    error "Helper template not found: ${template}"
    exit 1
  fi

  local helper_tmp=""
  helper_tmp=$(mktemp "${HELPER_FILE}.XXXXXX")
  _CLEANUP_FILES+=("$helper_tmp")
  sed "s|__PROFILE__|${DATABRICKS_PROFILE}|g; s|__HOST__|${DATABRICKS_HOST}|g; s|__SETUP_SCRIPT__|${setup_script}|g" "$template" > "$helper_tmp"
  mv "$helper_tmp" "$HELPER_FILE"
  chmod 700 "$HELPER_FILE"
  debug "write_helper: wrote ${HELPER_FILE} (profile=${DATABRICKS_PROFILE}, host=${DATABRICKS_HOST})"
  success "Helper script written to ${HELPER_FILE}."
}

register_plugin() {
  if [[ -f "${SCRIPT_DIR}/.claude-plugin/plugin.json" ]]; then
    local PLUGINS_FILE="$HOME/.claude/plugins/installed_plugins.json"
    mkdir -p "$(dirname "$PLUGINS_FILE")"

    local NEEDS_INSTALL=true
    if [[ -f "$PLUGINS_FILE" ]]; then
      local existing_path=""
      existing_path=$(jq -r '.["fmapi-codingagent"].installPath // empty' "$PLUGINS_FILE" 2>/dev/null) || true
      [[ "$existing_path" == "$SCRIPT_DIR" ]] && NEEDS_INSTALL=false
    fi

    if [[ "$NEEDS_INSTALL" == true ]]; then
      if [[ -f "$PLUGINS_FILE" ]]; then
        local plugin_tmp=""
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

    # 3. Gateway connectivity (if enabled)
    if [[ "${AI_GATEWAY_ENABLED:-false}" == "true" ]] && [[ -n "${WORKSPACE_ID:-}" ]]; then
      local gw_url="https://${WORKSPACE_ID}.ai-gateway.cloud.databricks.com/anthropic/v1/messages"
      local gw_code=""
      gw_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
        -H "Authorization: Bearer ${oauth_tok}" \
        "$gw_url" 2>/dev/null) || true
      if [[ -n "$gw_code" && "$gw_code" != "000" ]]; then
        success "AI Gateway v2 reachable (HTTP ${gw_code})."
      else
        echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Cannot reach AI Gateway v2 at ${gw_url}."
        (( warnings++ )) || true
      fi
    fi

    # 4. Configured models exist and are ready
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
  if [[ "${AI_GATEWAY_ENABLED:-false}" == "true" ]]; then
    local gw_base_url=""
    gw_base_url=$(_build_base_url "$DATABRICKS_HOST" "true" "${WORKSPACE_ID:-}")
    echo -e "  ${DIM}Routing${RESET}    ${BOLD}AI Gateway v2 (beta)${RESET}"
    echo -e "  ${DIM}Workspace ID${RESET} ${BOLD}${WORKSPACE_ID}${RESET}"
    echo -e "  ${DIM}Base URL${RESET}   ${BOLD}${gw_base_url}${RESET}"
  else
    echo -e "  ${DIM}Routing${RESET}    ${BOLD}Serving Endpoints (v1)${RESET}"
  fi
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

  # Routing
  echo -e "  ${BOLD}Routing${RESET}"
  if [[ "${AI_GATEWAY_ENABLED:-false}" == "true" ]]; then
    local dry_ws_id="${_PENDING_WORKSPACE_ID:-<to be detected>}"
    local dry_base_url=""
    if [[ "$dry_ws_id" != "<to be detected>" ]]; then
      dry_base_url=$(_build_base_url "$DATABRICKS_HOST" "true" "$dry_ws_id")
    else
      dry_base_url="https://<workspace-id>.ai-gateway.cloud.databricks.com/anthropic"
    fi
    echo -e "  ${CYAN}::${RESET}  Mode: ${BOLD}AI Gateway v2 (beta)${RESET}"
    echo -e "  ${CYAN}::${RESET}  Workspace ID: ${BOLD}${dry_ws_id}${RESET}"
    echo -e "  ${CYAN}::${RESET}  Base URL: ${BOLD}${dry_base_url}${RESET}"
  else
    echo -e "  ${CYAN}::${RESET}  Mode: ${BOLD}Serving Endpoints (v1)${RESET}"
  fi
  echo ""

  # Settings
  local dry_run_base_url=""
  if [[ "${AI_GATEWAY_ENABLED:-false}" == "true" ]]; then
    local ws_id_for_url="${_PENDING_WORKSPACE_ID:-<workspace-id>}"
    dry_run_base_url=$(_build_base_url "$DATABRICKS_HOST" "true" "$ws_id_for_url")
  else
    dry_run_base_url=$(_build_base_url "$DATABRICKS_HOST" "false" "")
  fi
  echo -e "  ${BOLD}Settings${RESET}"
  echo -e "  ${CYAN}::${RESET}  Settings file: ${BOLD}${SETTINGS_FILE}${RESET}"
  if [[ -f "$SETTINGS_FILE" ]]; then
    echo -e "       ${DIM}(exists — FMAPI keys would be merged)${RESET}"
  else
    echo -e "       ${DIM}(would be created)${RESET}"
  fi
  echo -e "  ${CYAN}::${RESET}  Env vars that would be set:"
  echo -e "       ANTHROPIC_MODEL=${BOLD}${ANTHROPIC_MODEL}${RESET}"
  echo -e "       ANTHROPIC_BASE_URL=${BOLD}${dry_run_base_url}${RESET}"
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

_show_reuse_summary() {
  echo -e "\n  ${BOLD}Existing configuration found:${RESET}\n"
  echo -e "  ${DIM}Workspace${RESET}  ${BOLD}${CFG_HOST}${RESET}"
  echo -e "  ${DIM}Profile${RESET}    ${BOLD}${CFG_PROFILE:-fmapi-claudecode-profile}${RESET}"
  echo -e "  ${DIM}TTL${RESET}        ${BOLD}${CFG_TTL:-60}m${RESET}"
  echo -e "  ${DIM}Model${RESET}      ${BOLD}${CFG_MODEL:-databricks-claude-opus-4-6}${RESET}"
  echo -e "  ${DIM}Opus${RESET}       ${BOLD}${CFG_OPUS:-databricks-claude-opus-4-6}${RESET}"
  echo -e "  ${DIM}Sonnet${RESET}     ${BOLD}${CFG_SONNET:-databricks-claude-sonnet-4-6}${RESET}"
  echo -e "  ${DIM}Haiku${RESET}      ${BOLD}${CFG_HAIKU:-databricks-claude-haiku-4-5}${RESET}"
  if [[ "${CFG_AI_GATEWAY:-}" == "true" ]]; then
    echo -e "  ${DIM}Routing${RESET}    ${BOLD}AI Gateway v2 (beta)${RESET}"
    echo -e "  ${DIM}Workspace ID${RESET} ${BOLD}${CFG_WORKSPACE_ID:-unknown}${RESET}"
  else
    echo -e "  ${DIM}Routing${RESET}    ${BOLD}Serving Endpoints (v1)${RESET}"
  fi
  echo -e "  ${DIM}Settings${RESET}   ${BOLD}${CFG_SETTINGS_FILE}${RESET}"
  echo ""

  select_option "Keep this configuration?" \
    "Yes, proceed|re-run setup with existing config" \
    "No, reconfigure|start fresh with all prompts"

  if [[ "$SELECT_RESULT" -eq 1 ]]; then
    return 0
  fi
  return 1
}

do_setup() {
  echo -e "\n${BOLD}  Claude Code x Databricks FMAPI Setup${RESET}\n"

  # Fast-path: re-running with existing config — show summary + confirm
  if [[ "$NON_INTERACTIVE" != true ]] && [[ "$DRY_RUN" != true ]] && command -v jq &>/dev/null; then
    CFG_FOUND=false CFG_HOST="" CFG_PROFILE=""
    CFG_MODEL="" CFG_OPUS="" CFG_SONNET="" CFG_HAIKU=""
    CFG_TTL=""
    CFG_SETTINGS_FILE="" CFG_HELPER_FILE=""
    discover_config
    if [[ "$CFG_FOUND" == true ]] && [[ -n "$CFG_HOST" ]]; then
      if _show_reuse_summary; then
        NON_INTERACTIVE=true
        # Populate CLI_* from CFG_* (only if CLI_* is empty — preserves explicit flags)
        [[ -z "$CLI_HOST" ]]     && CLI_HOST="$CFG_HOST"
        [[ -z "$CLI_PROFILE" ]]  && CLI_PROFILE="${CFG_PROFILE:-fmapi-claudecode-profile}"
        [[ -z "$CLI_TTL" ]]      && CLI_TTL="${CFG_TTL:-60}"
        [[ -z "$CLI_MODEL" ]]    && CLI_MODEL="${CFG_MODEL:-databricks-claude-opus-4-6}"
        [[ -z "$CLI_OPUS" ]]     && CLI_OPUS="${CFG_OPUS:-databricks-claude-opus-4-6}"
        [[ -z "$CLI_SONNET" ]]   && CLI_SONNET="${CFG_SONNET:-databricks-claude-sonnet-4-6}"
        [[ -z "$CLI_HAIKU" ]]    && CLI_HAIKU="${CFG_HAIKU:-databricks-claude-haiku-4-5}"
        [[ -z "$CLI_AI_GATEWAY" ]] && CLI_AI_GATEWAY="${CFG_AI_GATEWAY:-false}"
        [[ -z "$CLI_WORKSPACE_ID" ]] && CLI_WORKSPACE_ID="${CFG_WORKSPACE_ID:-}"
        # Derive settings location from discovered settings file path
        if [[ -z "$CLI_SETTINGS_LOCATION" ]] && [[ -n "$CFG_SETTINGS_FILE" ]]; then
          local cfg_base="${CFG_SETTINGS_FILE%/.claude/settings.json}"
          if [[ "$cfg_base" == "$HOME" ]]; then
            CLI_SETTINGS_LOCATION="home"
          else
            CLI_SETTINGS_LOCATION="$cfg_base"
          fi
        fi
      fi
      # If _show_reuse_summary returns 1 (reconfigure), fall through to normal flow
    fi
  fi

  gather_config_pre_auth

  if [[ "$DRY_RUN" == true ]]; then
    gather_config_models
    print_dry_run_plan
    exit 0
  fi

  install_dependencies
  authenticate
  resolve_workspace_id

  # Show available Claude endpoints before model selection (interactive only)
  if [[ "$NON_INTERACTIVE" != true ]]; then
    if _fetch_endpoints "$DATABRICKS_PROFILE" 2>/dev/null; then
      echo -e "\n${BOLD}Available Claude endpoints${RESET}\n"
      if ! _display_claude_endpoints; then
        info "No Claude/Anthropic endpoints found. You can still enter model names manually."
      fi
      echo ""
    fi
  fi

  gather_config_models

  write_settings
  ensure_onboarding
  write_helper
  register_plugin
  run_smoke_test
  print_summary
}
