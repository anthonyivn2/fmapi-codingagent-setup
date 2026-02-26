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

_OS_TYPE="$(uname -s 2>/dev/null || echo 'Unknown')"

info()    { echo -e "  ${CYAN}::${RESET} $1"; }
success() { echo -e "  ${GREEN}${BOLD}ok${RESET} $1"; }
error()   { echo -e "\n  ${RED}${BOLD}!! ERROR${RESET}${RED} $1${RESET}\n" >&2; }

# ── Utilities ─────────────────────────────────────────────────────────────────

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

# Require a command or exit with an error message
require_cmd() {
  local cmd="$1" msg="$2"
  command -v "$cmd" &>/dev/null || { error "$msg"; exit 1; }
}

# Platform-appropriate install hint for jq
_jq_install_hint() {
  if [[ "$_OS_TYPE" == "Linux" ]]; then
    echo "sudo apt-get install -y jq  (or sudo yum install -y jq)"
  else
    echo "brew install jq"
  fi
}

# Prompt for a value, respecting CLI flags and non-interactive mode.
# Usage: prompt_value VAR_NAME "Label" "cli_value" "default_value"
prompt_value() {
  local var_name="$1" label="$2" cli_val="$3" default="$4"
  local _pv_input=""
  if [[ -n "$cli_val" ]]; then
    printf -v "$var_name" '%s' "$cli_val"
  elif [[ "$NON_INTERACTIVE" == true ]]; then
    printf -v "$var_name" '%s' "$default"
  elif [[ -n "$default" ]]; then
    read -rp "$(echo -e "  ${CYAN}?${RESET} ${label} ${DIM}[${default}]${RESET}: ")" _pv_input
    printf -v "$var_name" '%s' "${_pv_input:-$default}"
  else
    read -rp "$(echo -e "  ${CYAN}?${RESET} ${label}: ")" _pv_input
    printf -v "$var_name" '%s' "$_pv_input"
  fi
}

# Interactive selector
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

# ── Config discovery ──────────────────────────────────────────────────────────
# Discover existing FMAPI configuration from settings and helper files.
# Sets CFG_* variables for use by callers.
discover_config() {
  CFG_FOUND=false
  CFG_HOST="" CFG_PROFILE=""
  CFG_MODEL="" CFG_OPUS="" CFG_SONNET="" CFG_HAIKU=""
  CFG_TTL=""
  CFG_SETTINGS_FILE="" CFG_HELPER_FILE=""

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
    fi

    # Parse model names from settings.json env block
    CFG_MODEL=$(jq -r '.env.ANTHROPIC_MODEL // empty' "$abs_path" 2>/dev/null) || true
    CFG_OPUS=$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL // empty' "$abs_path" 2>/dev/null) || true
    CFG_SONNET=$(jq -r '.env.ANTHROPIC_DEFAULT_SONNET_MODEL // empty' "$abs_path" 2>/dev/null) || true
    CFG_HAIKU=$(jq -r '.env.ANTHROPIC_DEFAULT_HAIKU_MODEL // empty' "$abs_path" 2>/dev/null) || true

    local cfg_ttl_ms=""
    cfg_ttl_ms=$(jq -r '.env.CLAUDE_CODE_API_KEY_HELPER_TTL_MS // empty' "$abs_path" 2>/dev/null) || true
    [[ -n "$cfg_ttl_ms" ]] && CFG_TTL=$(( cfg_ttl_ms / 60000 ))

    break  # Use first match
  done
}

# ── Config file loading ──────────────────────────────────────────────────────

# Valid keys in config files (version is handled separately)
_CONFIG_VALID_KEYS=("host" "profile" "model" "opus" "sonnet" "haiku" "ttl" "settings_location")

# Load and validate a local JSON config file.
# Populates FILE_* variables for use in gather_config priority chain.
# Usage: load_config_file /path/to/config.json
load_config_file() {
  local path="$1"

  # File must exist and be readable
  [[ -f "$path" ]] || { error "Config file not found: $path"; exit 1; }
  [[ -r "$path" ]] || { error "Config file is not readable: $path"; exit 1; }

  # Validate JSON
  jq empty "$path" 2>/dev/null || { error "Config file is not valid JSON: $path"; exit 1; }

  # Validate version (if present, must be 1)
  local version=""
  version=$(jq -r '.version // empty' "$path") || true
  if [[ -n "$version" ]] && [[ "$version" != "1" ]]; then
    error "Unsupported config file version: $version (expected: 1)."
    exit 1
  fi

  # Reject unknown keys
  local unknown=""
  unknown=$(jq -r 'keys[] | select(. != "version" and . != "host" and . != "profile" and . != "model" and . != "opus" and . != "sonnet" and . != "haiku" and . != "ttl" and . != "settings_location")' "$path") || true
  if [[ -n "$unknown" ]]; then
    local unknown_list=""
    unknown_list=$(echo "$unknown" | paste -sd ',' - | sed 's/,/, /g')
    local valid_list=""
    valid_list=$(printf '%s' "version, "; printf '%s, ' "${_CONFIG_VALID_KEYS[@]}" | sed 's/, $//')
    error "Unknown keys in config file: $unknown_list. Valid keys: $valid_list"
    exit 1
  fi

  # Read values
  FILE_HOST=$(jq -r '.host // empty' "$path") || true
  FILE_PROFILE=$(jq -r '.profile // empty' "$path") || true
  FILE_MODEL=$(jq -r '.model // empty' "$path") || true
  FILE_OPUS=$(jq -r '.opus // empty' "$path") || true
  FILE_SONNET=$(jq -r '.sonnet // empty' "$path") || true
  FILE_HAIKU=$(jq -r '.haiku // empty' "$path") || true
  FILE_SETTINGS_LOCATION=$(jq -r '.settings_location // empty' "$path") || true

  local raw_ttl=""
  raw_ttl=$(jq -r '.ttl // empty' "$path") || true
  if [[ -n "$raw_ttl" ]]; then
    if ! [[ "$raw_ttl" =~ ^[0-9]+$ ]] || [[ "$raw_ttl" -le 0 ]]; then
      error "Config file: ttl must be a positive integer (minutes). Got: $raw_ttl"
      exit 1
    fi
    if [[ "$raw_ttl" -gt 60 ]]; then
      error "Config file: ttl cannot exceed 60 minutes. Got: $raw_ttl"
      exit 1
    fi
    FILE_TTL="$raw_ttl"
  fi

  # Validate host format (if present)
  if [[ -n "$FILE_HOST" ]] && [[ "$FILE_HOST" != https://* ]]; then
    error "Config file: host must start with https://. Got: $FILE_HOST"
    exit 1
  fi

  # Validate profile format (if present)
  if [[ -n "$FILE_PROFILE" ]] && ! [[ "$FILE_PROFILE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Config file: invalid profile name '$FILE_PROFILE'. Use letters, numbers, hyphens, and underscores."
    exit 1
  fi
}

# Fetch a remote JSON config and delegate to load_config_file.
# Usage: load_config_url https://example.com/config.json
load_config_url() {
  local url="$1"

  # Enforce HTTPS
  [[ "$url" == https://* ]] || { error "Config URL must use HTTPS."; exit 1; }

  # Download to temp file
  local tmp_config=""
  tmp_config=$(mktemp "${TMPDIR:-/tmp}/fmapi-config-XXXXXX.json")
  _CLEANUP_FILES+=("$tmp_config")

  local http_code=""
  http_code=$(curl -fsSL -w '%{http_code}' -o "$tmp_config" "$url" 2>/dev/null) || {
    error "Failed to fetch config from URL: $url"
    exit 1
  }

  # Check for non-2xx (curl -f should catch most, but be safe)
  if [[ -z "$http_code" ]] || [[ "${http_code:0:1}" != "2" ]]; then
    error "Failed to fetch config from URL: $url (HTTP $http_code)"
    exit 1
  fi

  load_config_file "$tmp_config"
}

# ── Shared helpers ────────────────────────────────────────────────────────────

# Get an OAuth token for the given profile (or $CFG_PROFILE).
# Prints the token on stdout, returns 1 on failure.
_get_oauth_token() {
  local profile="${1:-$CFG_PROFILE}"
  [[ -z "$profile" ]] && return 1
  command -v databricks &>/dev/null || return 1
  local tok=""
  tok=$(databricks auth token --profile "$profile" --output json 2>/dev/null \
    | jq -r '.access_token // empty') || true
  [[ -n "$tok" ]] && { echo "$tok"; return 0; }
  return 1
}

# Fetch all serving endpoints into _ENDPOINTS_JSON.
# Requires databricks CLI and a valid profile. Returns 1 on failure.
_ENDPOINTS_JSON=""
_fetch_endpoints() {
  local profile="${1:-$CFG_PROFILE}"
  _ENDPOINTS_JSON=""
  [[ -z "$profile" ]] && return 1
  _ENDPOINTS_JSON=$(databricks serving-endpoints list --profile "$profile" --output json 2>/dev/null) || true
  [[ -n "$_ENDPOINTS_JSON" ]] && return 0
  return 1
}

# Validate configured models against _ENDPOINTS_JSON.
# Prints PASS/WARN/FAIL/SKIP per model. Sets _VALIDATE_ALL_PASS=true|false.
_VALIDATE_ALL_PASS=true
_validate_models_report() {
  _VALIDATE_ALL_PASS=true
  local models=()
  local labels=()

  # Build list of (label, model_name) pairs — skip unconfigured
  if [[ -n "$CFG_MODEL" ]]; then
    labels+=("Model")
    models+=("$CFG_MODEL")
  fi
  if [[ -n "$CFG_OPUS" ]]; then
    labels+=("Opus")
    models+=("$CFG_OPUS")
  fi
  if [[ -n "$CFG_SONNET" ]]; then
    labels+=("Sonnet")
    models+=("$CFG_SONNET")
  fi
  if [[ -n "$CFG_HAIKU" ]]; then
    labels+=("Haiku")
    models+=("$CFG_HAIKU")
  fi

  if [[ ${#models[@]} -eq 0 ]]; then
    echo -e "  ${DIM}SKIP${RESET}  No models configured"
    return 0
  fi

  local i
  for i in "${!models[@]}"; do
    local label="${labels[$i]}"
    local model="${models[$i]}"
    local padded
    padded=$(printf '%-8s' "$label")

    if [[ -z "$_ENDPOINTS_JSON" ]]; then
      echo -e "  ${YELLOW}${BOLD}WARN${RESET}  ${padded}${model}  ${DIM}(could not fetch endpoints)${RESET}"
      _VALIDATE_ALL_PASS=false
      continue
    fi

    local state=""
    state=$(echo "$_ENDPOINTS_JSON" | jq -r --arg name "$model" \
      '.[] | select(.name == $name) | .state.ready // .state // "UNKNOWN"' 2>/dev/null | head -1) || true

    if [[ -z "$state" ]]; then
      echo -e "  ${RED}${BOLD}FAIL${RESET}  ${padded}${model}  ${DIM}(not found)${RESET}"
      _VALIDATE_ALL_PASS=false
    elif [[ "$state" == "READY" ]]; then
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  ${padded}${model}"
    else
      echo -e "  ${YELLOW}${BOLD}WARN${RESET}  ${padded}${model}  ${DIM}(state: ${state})${RESET}"
      _VALIDATE_ALL_PASS=false
    fi
  done
}

# ── Commands ──────────────────────────────────────────────────────────────────

do_status() {
  require_cmd jq "jq is required for status. Install with: $(_jq_install_hint)"

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
  require_cmd jq "jq is required for reauth. Install with: $(_jq_install_hint)"
  require_cmd databricks "Databricks CLI is required for reauth. Install with: brew tap databricks/tap && brew install databricks"

  discover_config

  if [[ "$CFG_FOUND" != true ]]; then
    error "No FMAPI configuration found. Run setup first."
    exit 1
  fi

  [[ -z "$CFG_PROFILE" ]] && { error "Could not determine profile from helper script."; exit 1; }
  [[ -z "$CFG_HOST" ]] && { error "Could not determine host from helper script."; exit 1; }

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

  require_cmd jq "jq is required for uninstall. Install with: $(_jq_install_hint)"

  # ── Discover FMAPI artifacts ──────────────────────────────────────────────
  declare -a helper_scripts=()
  declare -a settings_files=()
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
  if [[ ${#helper_scripts[@]} -eq 0 && ${#settings_files[@]} -eq 0 ]]; then
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

  # ── Confirm removal ──────────────────────────────────────────────────────
  select_option "Remove FMAPI artifacts?" \
    "Yes|remove artifacts listed above" \
    "No|cancel and exit"
  [[ "$SELECT_RESULT" -ne 1 ]] && { info "Cancelled."; exit 0; }

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

  # ── Summary ──────────────────────────────────────────────────────────────
  echo -e "\n${GREEN}${BOLD}  Uninstall complete!${RESET}\n"
}

do_list_models() {
  require_cmd jq "jq is required for list-models. Install with: $(_jq_install_hint)"
  require_cmd databricks "Databricks CLI is required for list-models. Install with: brew tap databricks/tap && brew install databricks"

  discover_config

  if [[ "$CFG_FOUND" != true ]]; then
    error "No FMAPI configuration found. Run setup first."
    exit 1
  fi

  [[ -z "$CFG_PROFILE" ]] && { error "Could not determine profile from helper script."; exit 1; }
  [[ -z "$CFG_HOST" ]] && { error "Could not determine host from helper script."; exit 1; }

  # Verify OAuth is valid
  if ! _get_oauth_token "$CFG_PROFILE" >/dev/null 2>&1; then
    error "OAuth session expired or invalid. Run: bash setup-fmapi-claudecode.sh --reauth"
    exit 1
  fi

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

  # Filter to Claude/Anthropic endpoints only
  local filtered=""
  filtered=$(echo "$_ENDPOINTS_JSON" | jq '[.[] | select(.name | test("claude|anthropic"; "i"))]') || true
  local count=""
  count=$(echo "$filtered" | jq 'length') || true
  if [[ "$count" == "0" || -z "$count" ]]; then
    info "No Claude/Anthropic serving endpoints found in this workspace."
    echo ""
    exit 0
  fi

  # Print table header — pad plain text first, then wrap with BOLD
  local col_w=44
  local state_w=12
  local hdr_name hdr_state
  hdr_name=$(printf "%-${col_w}s" "ENDPOINT NAME")
  hdr_state=$(printf "%-${state_w}s" "STATE")
  echo -e "     ${BOLD}${hdr_name}${RESET} ${BOLD}${hdr_state}${RESET} ${BOLD}TYPE${RESET}"
  echo -e "  ${DIM}$(printf '%.0s─' {1..70})${RESET}"

  # Print each endpoint — pad plain text first, then wrap with color to keep columns aligned
  echo "$filtered" | jq -r '.[] | [.name, (.state.ready // .state // "UNKNOWN"), (.endpoint_type // .task // "unknown")] | @tsv' 2>/dev/null \
  | while IFS=$'\t' read -r name state etype; do
    local marker="   "
    local display_name="$name"
    if [[ ${#display_name} -gt $col_w ]]; then
      display_name="${display_name:0:$((col_w - 1))}…"
    fi
    local padded_name padded_state
    padded_name=$(printf "%-${col_w}s" "$display_name")
    padded_state=$(printf "%-${state_w}s" "$state")

    # Highlight currently configured models
    if array_contains "$name" ${configured_models[@]+"${configured_models[@]}"}; then
      marker=" ${GREEN}>${RESET} "
      padded_name="${GREEN}${BOLD}${padded_name}${RESET}"
    fi

    if [[ "$state" == "READY" ]]; then
      padded_state="${GREEN}$(printf "%-${state_w}s" "$state")${RESET}"
    elif [[ "$state" == "NOT_READY" ]]; then
      padded_state="${YELLOW}$(printf "%-${state_w}s" "$state")${RESET}"
    fi

    echo -e "  ${marker}${padded_name} ${padded_state} ${etype}"
  done

  # Legend
  echo ""
  echo -e "  ${GREEN}>${RESET} ${DIM}Currently configured${RESET}"
  echo ""
}

do_validate_models() {
  require_cmd jq "jq is required for validate-models. Install with: $(_jq_install_hint)"
  require_cmd databricks "Databricks CLI is required for validate-models. Install with: brew tap databricks/tap && brew install databricks"

  discover_config

  if [[ "$CFG_FOUND" != true ]]; then
    error "No FMAPI configuration found. Run setup first."
    exit 1
  fi

  [[ -z "$CFG_PROFILE" ]] && { error "Could not determine profile from helper script."; exit 1; }

  # Verify OAuth is valid
  if ! _get_oauth_token "$CFG_PROFILE" >/dev/null 2>&1; then
    error "OAuth session expired or invalid. Run: bash setup-fmapi-claudecode.sh --reauth"
    exit 1
  fi

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

do_doctor() {
  echo -e "\n${BOLD}  FMAPI Doctor${RESET}\n"

  local any_fail=false

  # ── 1. Dependencies ──────────────────────────────────────────────────────
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
      local fix=""
      case "$dep_name" in
        jq)
          if [[ "$_OS_TYPE" == "Linux" ]]; then
            fix="sudo apt-get install -y jq (or sudo yum install -y jq)"
          else
            fix="brew install jq"
          fi
          ;;
        databricks)
          if [[ "$_OS_TYPE" == "Linux" ]]; then
            fix="curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh"
          else
            fix="brew tap databricks/tap && brew install databricks"
          fi
          ;;
        claude)     fix="curl -fsSL https://claude.ai/install.sh | bash" ;;
        curl)
          if [[ "$_OS_TYPE" == "Linux" ]]; then
            fix="sudo apt-get install -y curl (or sudo yum install -y curl)"
          else
            fix="brew install curl"
          fi
          ;;
      esac
      echo -e "  ${RED}${BOLD}FAIL${RESET}  ${dep_name}  ${DIM}Fix: ${fix}${RESET}"
      deps_ok=false
      any_fail=true
    fi
  done
  echo ""

  # ── 2. Configuration ─────────────────────────────────────────────────────
  echo -e "  ${BOLD}Configuration${RESET}"

  if ! command -v jq &>/dev/null; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  Cannot check configuration (jq not installed)"
    echo ""
    discover_config  # still sets CFG_FOUND=false
  else
    discover_config

    if [[ "$CFG_FOUND" != true ]]; then
      echo -e "  ${RED}${BOLD}FAIL${RESET}  No FMAPI configuration found  ${DIM}Fix: run setup first${RESET}"
      any_fail=true
      echo ""
    else
      # Settings file exists and is valid JSON
      if [[ -f "$CFG_SETTINGS_FILE" ]]; then
        if jq empty "$CFG_SETTINGS_FILE" 2>/dev/null; then
          echo -e "  ${GREEN}${BOLD}PASS${RESET}  Settings file is valid JSON  ${DIM}${CFG_SETTINGS_FILE}${RESET}"
        else
          echo -e "  ${RED}${BOLD}FAIL${RESET}  Settings file is invalid JSON  ${DIM}${CFG_SETTINGS_FILE}${RESET}"
          any_fail=true
        fi
      else
        echo -e "  ${RED}${BOLD}FAIL${RESET}  Settings file not found  ${DIM}${CFG_SETTINGS_FILE}${RESET}"
        any_fail=true
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
        any_fail=true
      fi

      # Helper script exists and is executable
      if [[ -n "$CFG_HELPER_FILE" && -f "$CFG_HELPER_FILE" ]]; then
        if [[ -x "$CFG_HELPER_FILE" ]]; then
          echo -e "  ${GREEN}${BOLD}PASS${RESET}  Helper script exists and is executable  ${DIM}${CFG_HELPER_FILE}${RESET}"
        else
          echo -e "  ${RED}${BOLD}FAIL${RESET}  Helper script not executable  ${DIM}Fix: chmod 700 ${CFG_HELPER_FILE}${RESET}"
          any_fail=true
        fi
      elif [[ -n "$CFG_HELPER_FILE" ]]; then
        echo -e "  ${RED}${BOLD}FAIL${RESET}  Helper script not found  ${DIM}${CFG_HELPER_FILE}${RESET}"
        any_fail=true
      fi
      echo ""
    fi
  fi

  # ── 3. Profile ───────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Profile${RESET}"
  if [[ -z "$CFG_PROFILE" ]]; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  No profile configured"
  elif [[ -f "$HOME/.databrickscfg" ]] && grep -q "^\[${CFG_PROFILE}\]" "$HOME/.databrickscfg" 2>/dev/null; then
    echo -e "  ${GREEN}${BOLD}PASS${RESET}  Profile '${CFG_PROFILE}' exists in ~/.databrickscfg"
  else
    echo -e "  ${RED}${BOLD}FAIL${RESET}  Profile '${CFG_PROFILE}' not found in ~/.databrickscfg  ${DIM}Fix: --reauth or re-run setup${RESET}"
    any_fail=true
  fi
  echo ""

  # ── 4. Auth ──────────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Auth${RESET}"
  if [[ -z "$CFG_PROFILE" ]]; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  No profile configured"
  elif ! command -v databricks &>/dev/null; then
    echo -e "  ${YELLOW}${BOLD}SKIP${RESET}  databricks CLI not installed"
  else
    if _get_oauth_token "$CFG_PROFILE" >/dev/null 2>&1; then
      echo -e "  ${GREEN}${BOLD}PASS${RESET}  OAuth token is valid"
    else
      echo -e "  ${RED}${BOLD}FAIL${RESET}  OAuth token expired or invalid  ${DIM}Fix: --reauth${RESET}"
      any_fail=true
    fi
  fi
  echo ""

  # ── 5. Connectivity ─────────────────────────────────────────────────────
  echo -e "  ${BOLD}Connectivity${RESET}"
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
        any_fail=true
      else
        echo -e "  ${RED}${BOLD}FAIL${RESET}  Cannot reach Databricks API  ${DIM}Fix: check network and ${CFG_HOST}${RESET}"
        any_fail=true
      fi
    fi
  fi
  echo ""

  # ── 6. Models ────────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Models${RESET}"
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
      any_fail=true
    fi
  fi
  echo ""

  # ── Summary ──────────────────────────────────────────────────────────────
  if [[ "$any_fail" == true ]]; then
    echo -e "  ${RED}${BOLD}Some checks failed.${RESET} Review the issues above.\n"
    exit 1
  else
    echo -e "  ${GREEN}${BOLD}All checks passed!${RESET}\n"
    exit 0
  fi
}

show_help() {
  cat <<'HELPTEXT'
Usage: bash setup-fmapi-claudecode.sh [OPTIONS]

Sets up Claude Code to use Databricks Foundation Model API (FMAPI).

Prerequisites:
  - macOS or Linux (dependencies installed automatically)
  - A Databricks workspace with Foundation Model API enabled
  - Access to Claude models via your Databricks workspace

Commands:
  --status              Show FMAPI configuration health dashboard
  --reauth              Re-authenticate Databricks OAuth session
  --doctor              Run comprehensive diagnostics (deps, config, auth, connectivity, models)
  --list-models         List all serving endpoints in the workspace
  --validate-models     Validate configured models exist and are ready
  --reinstall           Rerun setup using previously saved configuration
  --uninstall           Remove FMAPI helper scripts and settings
  -h, --help            Show this help message

Setup options (skip interactive prompts):
  --host URL            Databricks workspace URL (required for non-interactive)
  --profile NAME        CLI profile name (default: fmapi-claudecode-profile)
  --model MODEL         Primary model (default: databricks-claude-opus-4-6)
  --opus MODEL          Opus model (default: databricks-claude-opus-4-6)
  --sonnet MODEL        Sonnet model (default: databricks-claude-sonnet-4-6)
  --haiku MODEL         Haiku model (default: databricks-claude-haiku-4-5)
  --ttl MINUTES         Token refresh interval in minutes (default: 30, max: 60)
  --settings-location   Where to write settings: "home", "cwd", or path (default: home)

Config file options:
  --config PATH         Load configuration from a local JSON file
  --config-url URL      Load configuration from a remote JSON URL (HTTPS only)

Examples:
  # Interactive setup — prompts for everything
  bash setup-fmapi-claudecode.sh

  # Minimal non-interactive — only host required, rest uses defaults
  bash setup-fmapi-claudecode.sh --host https://my-workspace.cloud.databricks.com

  # Non-interactive with custom profile and model
  bash setup-fmapi-claudecode.sh --host https://my-workspace.cloud.databricks.com \
    --profile my-profile --model databricks-claude-sonnet-4-6

  # Setup from a config file
  bash setup-fmapi-claudecode.sh --config ./my-config.json

  # Setup from a remote config URL
  bash setup-fmapi-claudecode.sh --config-url https://example.com/fmapi-config.json

  # Config file with CLI overrides
  bash setup-fmapi-claudecode.sh --config ./my-config.json --model databricks-claude-sonnet-4-6

  # Check configuration health
  bash setup-fmapi-claudecode.sh --status

  # Re-authenticate expired OAuth session
  bash setup-fmapi-claudecode.sh --reauth

  # Run full diagnostics
  bash setup-fmapi-claudecode.sh --doctor

  # List available serving endpoints
  bash setup-fmapi-claudecode.sh --list-models

  # Validate configured models
  bash setup-fmapi-claudecode.sh --validate-models

  # Rerun setup with previous config (no prompts)
  bash setup-fmapi-claudecode.sh --reinstall

  # Uninstall all FMAPI artifacts
  bash setup-fmapi-claudecode.sh --uninstall

Troubleshooting:
  OAuth expired        Run: bash setup-fmapi-claudecode.sh --reauth
  ConnectionRefused    Run: bash setup-fmapi-claudecode.sh --reinstall
  "No config found"    Run setup first (without --status/--reauth)
  Wrong workspace URL  URL must start with https:// and have no trailing slash
  Permission denied    Helper script needs execute permission (chmod 700)
  Model not found      Run: bash setup-fmapi-claudecode.sh --list-models
  Unclear issue        Run: bash setup-fmapi-claudecode.sh --doctor
HELPTEXT
  exit 0
}

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
}

install_dependencies() {
  echo -e "\n${BOLD}Installing dependencies${RESET}"

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
  echo -e "\n${BOLD}Authenticating${RESET}"

  get_oauth_token() {
    databricks auth token --profile "$DATABRICKS_PROFILE" --output json 2>/dev/null \
      | jq -r '.access_token // empty'
  }

  OAUTH_TOKEN=$(get_oauth_token) || true
  if [[ -z "$OAUTH_TOKEN" ]]; then
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
  echo -e "\n${BOLD}Writing settings${RESET}"

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
  success "Settings written to ${SETTINGS_FILE}."
}

write_helper() {
  echo -e "\n${BOLD}API key helper${RESET}"

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

# Refresh token likely expired — attempt browser-based re-authentication
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

  local setup_script
  setup_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  helper_tmp=$(mktemp "${HELPER_FILE}.XXXXXX")
  _CLEANUP_FILES+=("$helper_tmp")
  sed "s|__PROFILE__|${DATABRICKS_PROFILE}|g; s|__HOST__|${DATABRICKS_HOST}|g; s|__SETUP_SCRIPT__|${setup_script}|g" "$HELPER_FILE" > "$helper_tmp"
  mv "$helper_tmp" "$HELPER_FILE"
  chmod 700 "$HELPER_FILE"
  success "Helper script written to ${HELPER_FILE}."
}

register_plugin() {
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
      success "Plugin registered (skills: /fmapi-codingagent-status, /fmapi-codingagent-reauth, /fmapi-codingagent-setup, /fmapi-codingagent-doctor, /fmapi-codingagent-list-models, /fmapi-codingagent-validate-models)."
    fi
  fi
}

run_smoke_test() {
  echo -e "\n${BOLD}Verifying setup${RESET}"

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

do_setup() {
  echo -e "\n${BOLD}  Claude Code x Databricks FMAPI Setup${RESET}\n"
  gather_config
  install_dependencies
  authenticate
  write_settings
  write_helper
  register_plugin
  run_smoke_test
  print_summary
}

# ── CLI flag parsing ──────────────────────────────────────────────────────────
CLI_HOST="" CLI_PROFILE="" CLI_MODEL="" CLI_OPUS="" CLI_SONNET="" CLI_HAIKU=""
CLI_TTL=""
CLI_SETTINGS_LOCATION=""
CLI_CONFIG_FILE="" CLI_CONFIG_URL=""
ACTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)      show_help ;;
    --status)       ACTION="status"; shift ;;
    --reauth)       ACTION="reauth"; shift ;;
    --uninstall)    ACTION="uninstall"; shift ;;
    --doctor)       ACTION="doctor"; shift ;;
    --list-models)  ACTION="list-models"; shift ;;
    --validate-models) ACTION="validate-models"; shift ;;
    --reinstall)    ACTION="reinstall"; shift ;;
    --host)         CLI_HOST="${2:-}"; [[ -z "$CLI_HOST" ]] && { error "--host requires a URL."; exit 1; }; shift 2 ;;
    --profile)      CLI_PROFILE="${2:-}"; [[ -z "$CLI_PROFILE" ]] && { error "--profile requires a name."; exit 1; }; shift 2 ;;
    --model)        CLI_MODEL="${2:-}"; [[ -z "$CLI_MODEL" ]] && { error "--model requires a value."; exit 1; }; shift 2 ;;
    --opus)         CLI_OPUS="${2:-}"; [[ -z "$CLI_OPUS" ]] && { error "--opus requires a value."; exit 1; }; shift 2 ;;
    --sonnet)       CLI_SONNET="${2:-}"; [[ -z "$CLI_SONNET" ]] && { error "--sonnet requires a value."; exit 1; }; shift 2 ;;
    --haiku)        CLI_HAIKU="${2:-}"; [[ -z "$CLI_HAIKU" ]] && { error "--haiku requires a value."; exit 1; }; shift 2 ;;
    --ttl)          CLI_TTL="${2:-}"; [[ -z "$CLI_TTL" ]] && { error "--ttl requires a value."; exit 1; }; shift 2 ;;
    --settings-location) CLI_SETTINGS_LOCATION="${2:-}"; [[ -z "$CLI_SETTINGS_LOCATION" ]] && { error "--settings-location requires a value."; exit 1; }; shift 2 ;;
    --config)       CLI_CONFIG_FILE="${2:-}"; [[ -z "$CLI_CONFIG_FILE" ]] && { error "--config requires a file path."; exit 1; }; shift 2 ;;
    --config-url)   CLI_CONFIG_URL="${2:-}"; [[ -z "$CLI_CONFIG_URL" ]] && { error "--config-url requires a URL."; exit 1; }; shift 2 ;;
    *)              error "Unknown option: $1"; echo "  Run with --help for usage." >&2; exit 1 ;;
  esac
done

# ── Mutual exclusion: --config and --config-url ──────────────────────────────
if [[ -n "$CLI_CONFIG_FILE" ]] && [[ -n "$CLI_CONFIG_URL" ]]; then
  error "Cannot use both --config and --config-url. Choose one."
  exit 1
fi

# ── Config file loading ──────────────────────────────────────────────────────
FILE_HOST="" FILE_PROFILE="" FILE_MODEL="" FILE_OPUS="" FILE_SONNET="" FILE_HAIKU=""
FILE_TTL="" FILE_SETTINGS_LOCATION=""

if [[ -n "$CLI_CONFIG_FILE" ]] || [[ -n "$CLI_CONFIG_URL" ]]; then
  require_cmd jq "jq is required to parse config files. Install with: $(_jq_install_hint)"
  if [[ -n "$CLI_CONFIG_FILE" ]]; then
    load_config_file "$CLI_CONFIG_FILE"
  else
    load_config_url "$CLI_CONFIG_URL"
  fi
fi

# ── Non-interactive mode ──────────────────────────────────────────────────────
NON_INTERACTIVE=false
[[ -n "$CLI_HOST" ]] && NON_INTERACTIVE=true
[[ -n "$CLI_CONFIG_FILE" || -n "$CLI_CONFIG_URL" ]] && NON_INTERACTIVE=true

# ── --reinstall: rerun setup with previous config ─────────────────────────────
if [[ "${ACTION}" == "reinstall" ]]; then
  require_cmd jq "jq is required for reinstall. Install with: $(_jq_install_hint)"
  discover_config
  if [[ "$CFG_FOUND" != true ]] || [[ -z "$CFG_HOST" ]]; then
    error "No existing FMAPI configuration found. Run setup first (without --reinstall)."
    exit 1
  fi
  info "Re-installing with existing config (${CFG_HOST}, profile: ${CFG_PROFILE:-fmapi-claudecode-profile})"
  NON_INTERACTIVE=true
fi

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${ACTION}" in
  status)          do_status; exit 0 ;;
  reauth)          do_reauth; exit 0 ;;
  doctor)          do_doctor; exit 0 ;;
  list-models)     do_list_models; exit 0 ;;
  validate-models) do_validate_models; exit 0 ;;
  uninstall)       do_uninstall; exit 0 ;;
esac

do_setup
