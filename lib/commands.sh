#!/bin/bash
# lib/commands.sh — All do_* command functions and show_help
# Sourced by setup-fmapi-claudecode.sh; do not run directly.

# ── Commands ──────────────────────────────────────────────────────────────────

do_status() {
  require_cmd jq "jq is required for status. Install with: $(_install_hint jq)"

  discover_config

  if [[ "$CFG_FOUND" != true ]]; then
    echo -e "\n${BOLD}  FMAPI Status${RESET}\n"
    info "No FMAPI configuration found."
    info "Run ${CYAN}bash setup-fmapi-claudecode.sh${RESET} to set up."
    echo ""
    exit 0
  fi

  echo -e "\n${BOLD}  FMAPI Status${RESET}\n"

  echo -e "  ${DIM}Version${RESET}    ${BOLD}${FMAPI_VERSION:-unknown}${RESET}"
  echo ""

  # ── Configuration ─────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Configuration${RESET}"
  echo -e "  ${DIM}Workspace${RESET}  ${BOLD}${CFG_HOST:-unknown}${RESET}"
  echo -e "  ${DIM}Profile${RESET}    ${BOLD}${CFG_PROFILE:-unknown}${RESET}"
  echo -e "  ${DIM}Model${RESET}      ${BOLD}${CFG_MODEL:-unknown}${RESET}"
  echo -e "  ${DIM}Opus${RESET}       ${BOLD}${CFG_OPUS:-unknown}${RESET}"
  echo -e "  ${DIM}Sonnet${RESET}     ${BOLD}${CFG_SONNET:-unknown}${RESET}"
  echo -e "  ${DIM}Haiku${RESET}      ${BOLD}${CFG_HAIKU:-unknown}${RESET}"
  if [[ -n "$CFG_TTL" ]]; then
    echo -e "  ${DIM}TTL${RESET}        ${BOLD}${CFG_TTL}m${RESET}"
  fi
  echo ""

  # ── Auth ─────────────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Auth${RESET}"
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
  echo ""
}

do_reauth() {
  _require_fmapi_config "reauth"

  if _is_headless; then
    echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Headless SSH session detected. Browser-based OAuth may not work."
  fi
  if [[ "$_IS_WSL" == true ]]; then
    if ! command -v wslview &>/dev/null && ! command -v xdg-open &>/dev/null; then
      warn "WSL detected but no browser opener found."
      info "If the browser does not open, install wslu: ${CYAN}sudo apt-get install -y wslu${RESET}"
    fi
  fi
  info "Re-authenticating with Databricks (profile: ${CFG_PROFILE}) ..."
  databricks auth login --host "$CFG_HOST" --profile "$CFG_PROFILE"

  # Verify success
  local oauth_tok=""
  oauth_tok=$(databricks auth token --profile "$CFG_PROFILE" --output json 2>/dev/null \
    | jq -r '.access_token // empty') || true

  if [[ -n "$oauth_tok" ]]; then
    success "OAuth session re-established for profile '${CFG_PROFILE}'."
  else
    error "Re-authentication failed. Try manually: databricks auth login --host ${CFG_HOST} --profile ${CFG_PROFILE}"
    exit 1
  fi
}

do_uninstall() {
  echo -e "\n${BOLD}  Claude Code x Databricks FMAPI — Uninstall${RESET}\n"

  require_cmd jq "jq is required for uninstall. Install with: $(_install_hint jq)"

  # ── Discover FMAPI artifacts ──────────────────────────────────────────────
  local default_install_dir="${HOME}/.fmapi-codingagent-setup"

  declare -a helper_scripts=()
  declare -a settings_files=()

  # Try to discover any custom settings location from existing config
  local extra_candidate=""
  if command -v databricks &>/dev/null; then
    discover_config
    if [[ "$CFG_FOUND" == true && -n "$CFG_SETTINGS_FILE" ]]; then
      extra_candidate="$CFG_SETTINGS_FILE"
    fi
  fi

  # Check well-known settings locations + any discovered custom location
  declare -a candidates=("$HOME/.claude/settings.json" "./.claude/settings.json")
  [[ -n "$extra_candidate" ]] && candidates+=("$extra_candidate")
  for candidate in "${candidates[@]}"; do
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
  if [[ ${#helper_scripts[@]} -eq 0 && ${#settings_files[@]} -eq 0 && ! -d "$default_install_dir" ]]; then
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

  if [[ ${#settings_files[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}Settings files (FMAPI keys only — other settings preserved):${RESET}"
    for sf in "${settings_files[@]}"; do
      echo -e "    ${DIM}${sf}${RESET}"
    done
    echo ""
  fi

  if [[ -d "$default_install_dir" ]]; then
    echo -e "  ${CYAN}Install directory:${RESET}"
    echo -e "    ${DIM}${default_install_dir}${RESET}"
    echo ""
  fi

  # ── Confirm removal ──────────────────────────────────────────────────────
  select_option "Remove FMAPI artifacts?" \
    "Yes|remove artifacts listed above" \
    "No|cancel and exit"
  if [[ "$SELECT_RESULT" -ne 1 ]]; then
    info "Cancelled."
    exit 0
  fi

  echo ""

  # ── Delete helper scripts ───────────────────────────────────────────────
  for hs in "${helper_scripts[@]}"; do
    rm -f "$hs"
    success "Deleted ${hs}."
  done

  # ── Clean up legacy cache files next to helper scripts ──────────────────
  for hs in "${helper_scripts[@]}"; do
    local cache_file=""
    cache_file="$(dirname "$hs")/.fmapi-pat-cache"
    if [[ -f "$cache_file" ]]; then
      rm -f "$cache_file"
      success "Deleted legacy cache ${cache_file}."
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

  # ── Remove default install directory ──────────────────────────────────────
  if [[ -d "$default_install_dir" ]]; then
    rm -rf "$default_install_dir"
    success "Removed install directory ${default_install_dir}."
  fi

  # ── Summary ──────────────────────────────────────────────────────────────
  echo -e "\n${GREEN}${BOLD}  Uninstall complete!${RESET}\n"
}

do_list_models() {
  _require_fmapi_config "list-models"
  if [[ -z "$CFG_HOST" ]]; then
    error "Could not determine host from helper script."
    exit 1
  fi
  _require_valid_oauth

  echo -e "\n${BOLD}  FMAPI Anthropic Claude Serving Endpoints${RESET}"
  echo -e "  ${DIM}Workspace: ${CFG_HOST}${RESET}\n"

  if ! _fetch_endpoints "$CFG_PROFILE"; then
    error "Failed to fetch serving endpoints. Check your network and profile."
    exit 1
  fi

  # Build configured models set for highlighting
  local configured_models=()
  [[ -n "$CFG_MODEL" ]] && configured_models+=("$CFG_MODEL")
  [[ -n "$CFG_OPUS" ]] && configured_models+=("$CFG_OPUS")
  [[ -n "$CFG_SONNET" ]] && configured_models+=("$CFG_SONNET")
  [[ -n "$CFG_HAIKU" ]] && configured_models+=("$CFG_HAIKU")

  if ! _display_claude_endpoints ${configured_models[@]+"${configured_models[@]}"}; then
    info "No Claude/Anthropic serving endpoints found in this workspace."
    echo ""
    exit 0
  fi

  # Legend
  echo ""
  echo -e "  ${GREEN}>${RESET} ${DIM}Currently configured${RESET}"
  echo ""
}

do_validate_models() {
  _require_fmapi_config "validate-models"
  _require_valid_oauth

  echo -e "\n${BOLD}  FMAPI Model Validation${RESET}\n"

  if ! _fetch_endpoints "$CFG_PROFILE"; then
    error "Failed to fetch serving endpoints. Check your network and profile."
    exit 1
  fi

  _validate_models_report

  echo ""

  if [[ "$_VALIDATE_ALL_PASS" != true ]]; then
    info "Some models failed validation. Run ${CYAN}--list-models${RESET} to see available endpoints."
    echo ""
    exit 1
  fi

  success "All configured models are available and ready."
  echo ""
}

# ── Doctor sub-functions ──────────────────────────────────────────────────────
# Each returns 0 on pass/skip, 1 on any failure.

_doctor_dependencies() {
  echo -e "  ${BOLD}Dependencies${RESET}"
  local deps_ok=true

  for dep_name in jq databricks claude curl; do
    if command -v "$dep_name" &>/dev/null; then
      local ver=""
      case "$dep_name" in
        jq)         ver=$(jq --version 2>/dev/null || echo "unknown") ;;
        databricks) ver=$(databricks --version 2>/dev/null | head -1 || echo "unknown") ;;
        claude)     ver=$(claude --version 2>/dev/null | head -1 || echo "unknown") ;;
        curl)       ver=$(curl --version 2>/dev/null | head -1 || echo "unknown") ;;
      esac
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  ${dep_name}  ${DIM}${ver}${RESET}"
    else
      echo -e "  ${RED}${BOLD}FAIL${RESET}  ${dep_name}  ${DIM}Fix: $(_install_hint "$dep_name")${RESET}"
      deps_ok=false
    fi
  done
  echo -e "  ${DIM}fmapi-codingagent-setup${RESET}  ${FMAPI_VERSION:-unknown}"
  echo ""
  [[ "$deps_ok" == true ]]
}

_doctor_environment() {
  echo -e "  ${BOLD}Environment${RESET}"
  echo -e "  ${DIM}INFO${RESET}  OS: ${_OS_TYPE}"

  if [[ "$_IS_WSL" == true ]]; then
    echo -e "  ${DIM}INFO${RESET}  WSL version: ${_WSL_VERSION:-unknown}  ${YELLOW}(experimental)${RESET}"
    [[ -n "${WSL_DISTRO_NAME:-}" ]] && \
      echo -e "  ${DIM}INFO${RESET}  WSL distro: ${WSL_DISTRO_NAME}"

    if command -v wslview &>/dev/null; then
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  wslview available (wslu installed)"
    elif command -v xdg-open &>/dev/null; then
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  xdg-open available"
    elif [[ -n "${BROWSER:-}" ]]; then
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  BROWSER env var set: ${BROWSER}"
    else
      echo -e "  ${YELLOW}${BOLD}WARN${RESET}  No browser opener found  ${DIM}Fix: sudo apt-get install -y wslu${RESET}"
    fi
  fi

  echo ""
  return 0  # Informational only, never fails
}

_doctor_configuration() {
  echo -e "  ${BOLD}Configuration${RESET}"
  local config_ok=true

  if ! command -v jq &>/dev/null; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  Cannot check configuration (jq not installed)"
    echo ""
    discover_config  # still sets CFG_FOUND=false
    return 0  # SKIP is not a failure
  fi

  discover_config

  if [[ "$CFG_FOUND" != true ]]; then
    echo -e "  ${RED}${BOLD}FAIL${RESET}  No FMAPI configuration found  ${DIM}Fix: run setup first${RESET}"
    echo ""
    return 1
  fi

  # Settings file exists and is valid JSON
  if [[ -f "$CFG_SETTINGS_FILE" ]]; then
    if jq empty "$CFG_SETTINGS_FILE" 2>/dev/null; then
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  Settings file is valid JSON  ${DIM}${CFG_SETTINGS_FILE}${RESET}"
    else
      echo -e "  ${RED}${BOLD}FAIL${RESET}  Settings file is invalid JSON  ${DIM}${CFG_SETTINGS_FILE}${RESET}"
      config_ok=false
    fi
  else
    echo -e "  ${RED}${BOLD}FAIL${RESET}  Settings file not found  ${DIM}${CFG_SETTINGS_FILE}${RESET}"
    config_ok=false
  fi

  # Required FMAPI keys present
  local required_keys=("ANTHROPIC_MODEL" "ANTHROPIC_BASE_URL" "ANTHROPIC_DEFAULT_OPUS_MODEL" "ANTHROPIC_DEFAULT_SONNET_MODEL" "ANTHROPIC_DEFAULT_HAIKU_MODEL")
  local missing_keys=()
  for key in "${required_keys[@]}"; do
    local val=""
    val=$(jq -r ".env.${key} // empty" "$CFG_SETTINGS_FILE" 2>/dev/null) || true
    [[ -z "$val" ]] && missing_keys+=("$key")
  done
  if [[ ${#missing_keys[@]} -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}PASS${RESET}  All required FMAPI env keys present"
  else
    echo -e "  ${RED}${BOLD}FAIL${RESET}  Missing env keys: ${missing_keys[*]}  ${DIM}Fix: re-run setup${RESET}"
    config_ok=false
  fi

  # Onboarding flag in ~/.claude.json
  local claude_json="$HOME/.claude.json"
  if [[ -f "$claude_json" ]]; then
    local ob_val=""
    ob_val=$(jq -r '.hasCompletedOnboarding // empty' "$claude_json" 2>/dev/null) || true
    if [[ "$ob_val" == "true" ]]; then
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  hasCompletedOnboarding is set  ${DIM}${claude_json}${RESET}"
    else
      echo -e "  ${RED}${BOLD}FAIL${RESET}  hasCompletedOnboarding not set  ${DIM}Fix: re-run setup or add to ${claude_json}${RESET}"
      config_ok=false
    fi
  else
    echo -e "  ${RED}${BOLD}FAIL${RESET}  ${claude_json} not found  ${DIM}Fix: re-run setup${RESET}"
    config_ok=false
  fi

  # Helper script exists and is executable
  if [[ -n "$CFG_HELPER_FILE" && -f "$CFG_HELPER_FILE" ]]; then
    if [[ -x "$CFG_HELPER_FILE" ]]; then
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  Helper script exists and is executable  ${DIM}${CFG_HELPER_FILE}${RESET}"
    else
      echo -e "  ${RED}${BOLD}FAIL${RESET}  Helper script not executable  ${DIM}Fix: chmod 700 ${CFG_HELPER_FILE}${RESET}"
      config_ok=false
    fi
  elif [[ -n "$CFG_HELPER_FILE" ]]; then
    echo -e "  ${RED}${BOLD}FAIL${RESET}  Helper script not found  ${DIM}${CFG_HELPER_FILE}${RESET}"
    config_ok=false
  fi
  echo ""
  [[ "$config_ok" == true ]]
}

_doctor_profile() {
  echo -e "  ${BOLD}Profile${RESET}"
  local profile_ok=true

  if [[ -z "$CFG_PROFILE" ]]; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  No profile configured"
  elif [[ -f "$HOME/.databrickscfg" ]] && grep -q "^\[${CFG_PROFILE}\]" "$HOME/.databrickscfg" 2>/dev/null; then
    echo -e "  ${GREEN}${BOLD}PASS${RESET}  Profile '${CFG_PROFILE}' exists in ~/.databrickscfg"
  else
    echo -e "  ${RED}${BOLD}FAIL${RESET}  Profile '${CFG_PROFILE}' not found in ~/.databrickscfg  ${DIM}Fix: --reauth or re-run setup${RESET}"
    profile_ok=false
  fi
  echo ""
  [[ "$profile_ok" == true ]]
}

_doctor_auth() {
  echo -e "  ${BOLD}Auth${RESET}"
  local auth_ok=true

  if [[ -z "$CFG_PROFILE" ]]; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  No profile configured"
  elif ! command -v databricks &>/dev/null; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  databricks CLI not installed"
  else
    if _get_oauth_token "$CFG_PROFILE" >/dev/null 2>&1; then
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  OAuth token is valid"
    else
      echo -e "  ${RED}${BOLD}FAIL${RESET}  OAuth token expired or invalid  ${DIM}Fix: --reauth${RESET}"
      auth_ok=false
    fi
    if _is_headless; then
      echo -e "  ${YELLOW}${BOLD}INFO${RESET}  Headless SSH session detected — browser-based OAuth will not work here"
    fi
  fi
  echo ""
  [[ "$auth_ok" == true ]]
}

_doctor_connectivity() {
  echo -e "  ${BOLD}Connectivity${RESET}"
  local conn_ok=true

  if [[ -z "$CFG_HOST" ]]; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  No host configured"
  elif ! command -v curl &>/dev/null; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  curl not installed"
  else
    local oauth_tok=""
    oauth_tok=$(_get_oauth_token "$CFG_PROFILE" 2>/dev/null) || true
    if [[ -z "$oauth_tok" ]]; then
      echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  Cannot test connectivity (no valid token)"
    else
      local http_code=""
      http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
        -H "Authorization: Bearer ${oauth_tok}" \
        "${CFG_HOST}/api/2.0/serving-endpoints" 2>/dev/null) || true
      if [[ "$http_code" == "200" ]]; then
        echo -e "  ${GREEN}${BOLD}PASS${RESET}  Databricks API reachable  ${DIM}${CFG_HOST}${RESET}"
      elif [[ -n "$http_code" && "$http_code" != "000" ]]; then
        echo -e "  ${YELLOW}${BOLD}WARN${RESET}  Databricks API returned HTTP ${http_code}  ${DIM}${CFG_HOST}${RESET}"
        conn_ok=false
      else
        echo -e "  ${RED}${BOLD}FAIL${RESET}  Cannot reach Databricks API  ${DIM}Fix: check network and ${CFG_HOST}${RESET}"
        conn_ok=false
      fi
    fi
  fi
  echo ""
  [[ "$conn_ok" == true ]]
}

_doctor_models() {
  echo -e "  ${BOLD}Models${RESET}"
  local models_ok=true

  if [[ "$CFG_FOUND" != true ]]; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  No configuration found"
  elif [[ -z "$CFG_PROFILE" ]] || ! command -v databricks &>/dev/null; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  Cannot validate models (missing profile or CLI)"
  elif ! _get_oauth_token "$CFG_PROFILE" >/dev/null 2>&1; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  Cannot validate models (auth failed)"
  else
    _fetch_endpoints "$CFG_PROFILE" || true
    _validate_models_report
    if [[ "$_VALIDATE_ALL_PASS" != true ]]; then
      models_ok=false
    fi
  fi
  echo ""
  [[ "$models_ok" == true ]]
}

do_self_update() {
  require_cmd git "git is required for self-update. Install git first."

  echo -e "\n${BOLD}  FMAPI Self-Update${RESET}\n"

  local current_version="${FMAPI_VERSION:-unknown}"
  info "Current version: ${BOLD}${current_version}${RESET}"
  info "Install path:    ${DIM}${SCRIPT_DIR}${RESET}"

  # ── Check if this is a git repo ──────────────────────────────────────────
  if [[ ! -d "${SCRIPT_DIR}/.git" ]]; then
    error "Not a git installation (no .git/ directory in ${SCRIPT_DIR})."
    info "Re-install with:"
    info "  ${CYAN}bash <(curl -sL https://raw.githubusercontent.com/anthonyivn2/fmapi-codingagent-setup/main/install.sh)${RESET}"
    exit 1
  fi

  # ── Detect current branch ────────────────────────────────────────────────
  local branch=""
  branch=$(git -C "${SCRIPT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null) || true
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    branch="main"
    debug "Detached HEAD detected, defaulting to main."
  fi
  debug "Branch: ${branch}"

  # ── Fetch and check for updates ──────────────────────────────────────────
  info "Checking for updates..."
  if ! git -C "${SCRIPT_DIR}" fetch --quiet origin "$branch" 2>/dev/null; then
    error "Failed to fetch from remote. Check your network connection."
    exit 1
  fi

  local local_rev="" remote_rev=""
  local_rev=$(git -C "${SCRIPT_DIR}" rev-parse HEAD)
  remote_rev=$(git -C "${SCRIPT_DIR}" rev-parse "origin/${branch}")

  if [[ "$local_rev" == "$remote_rev" ]]; then
    success "Already up to date (${current_version})."
    echo ""
    exit 0
  fi

  # ── Show what's changing ─────────────────────────────────────────────────
  local commit_count=""
  commit_count=$(git -C "${SCRIPT_DIR}" rev-list --count "HEAD..origin/${branch}")
  info "${commit_count} new commit(s) available."

  # ── Pull updates ─────────────────────────────────────────────────────────
  info "Updating..."
  if ! git -C "${SCRIPT_DIR}" pull --quiet origin "$branch" 2>/dev/null; then
    error "Failed to pull updates. You may have local changes."
    info "Fix with: ${CYAN}cd ${SCRIPT_DIR} && git stash && git pull origin ${branch}${RESET}"
    exit 1
  fi

  # ── Show new version ─────────────────────────────────────────────────────
  local new_version="unknown"
  if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
    new_version=$(tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION")
  fi

  success "Updated: ${current_version} → ${new_version}"
  echo ""
}

do_doctor() {
  echo -e "\n${BOLD}  FMAPI Doctor${RESET}\n"

  local any_fail=false

  _doctor_dependencies || any_fail=true
  _doctor_environment
  _doctor_configuration || any_fail=true
  _doctor_profile || any_fail=true
  _doctor_auth || any_fail=true
  _doctor_connectivity || any_fail=true
  _doctor_models || any_fail=true

  # ── Summary ──────────────────────────────────────────────────────────────
  if [[ "$any_fail" == true ]]; then
    echo -e "  ${RED}${BOLD}Some checks failed.${RESET} Review the issues above.\n"
    exit 1
  else
    echo -e "  ${GREEN}${BOLD}All checks passed!${RESET}\n"
    exit 0
  fi
}
