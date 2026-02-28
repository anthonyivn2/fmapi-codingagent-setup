#!/bin/bash
# lib/shared.sh — OAuth, endpoints, validation, and shared helpers
# Sourced by setup-fmapi-claudecode.sh; do not run directly.

# Get an OAuth token for the given profile (or $CFG_PROFILE).
# Prints the token on stdout, returns 1 on failure.
_get_oauth_token() {
  local profile="${1:-$CFG_PROFILE}"
  [[ -z "$profile" ]] && return 1
  command -v databricks &>/dev/null || return 1
  local tok=""
  tok=$(databricks auth token --profile "$profile" --output json 2>/dev/null \
    | jq -r '.access_token // empty') || true
  if [[ -n "$tok" ]]; then echo "$tok"; return 0; fi
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

# Display Claude/Anthropic endpoints from _ENDPOINTS_JSON as a formatted table.
# Accepts optional model names as positional args to highlight in the table.
# Returns 1 if no Claude endpoints found, 0 otherwise.
_display_claude_endpoints() {
  local highlight_models=("$@")

  # Filter to Claude/Anthropic endpoints only
  local filtered=""
  filtered=$(echo "$_ENDPOINTS_JSON" | jq '[.[] | select(.name | test("claude|anthropic"; "i"))]') || true
  local count=""
  count=$(echo "$filtered" | jq 'length') || true
  if [[ "$count" == "0" || -z "$count" ]]; then
    return 1
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

    # Highlight models passed as arguments
    if array_contains "$name" ${highlight_models[@]+"${highlight_models[@]}"}; then
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

  return 0
}

# ── Deduplication helpers ─────────────────────────────────────────────────────

# Detect headless SSH sessions (no browser for OAuth)
_is_headless() {
  # WSL can open a browser via Windows interop
  [[ "$_IS_WSL" == true ]] && return 1
  [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]] && [[ -z "${DISPLAY:-}" ]]
}

# Require FMAPI configuration: jq + databricks CLI + discover_config + checks.
# Exits with an error if any prerequisite is missing.
_require_fmapi_config() {
  local caller="${1:-command}"
  require_cmd jq "jq is required for ${caller}. Install with: $(_install_hint jq)"
  require_cmd databricks "Databricks CLI is required for ${caller}. Install with: $(_install_hint databricks)"
  discover_config
  if [[ "$CFG_FOUND" != true ]]; then
    error "No FMAPI configuration found. Run setup first."
    exit 1
  fi
  if [[ -z "$CFG_PROFILE" ]]; then
    error "Could not determine profile from helper script."
    exit 1
  fi
}

# Require a valid OAuth token (exits on failure)
_require_valid_oauth() {
  if ! _get_oauth_token "$CFG_PROFILE" >/dev/null 2>&1; then
    error "OAuth session expired or invalid. Run: bash setup-fmapi-claudecode.sh --reauth"
    exit 1
  fi
}
