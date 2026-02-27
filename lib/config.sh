#!/bin/bash
# lib/config.sh — Config discovery and file/URL loading
# Sourced by setup-fmapi-claudecode.sh; do not run directly.

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
      if [[ -z "$CFG_PROFILE" ]]; then CFG_PROFILE=$(sed -n 's/^PROFILE="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true; fi
      CFG_HOST=$(sed -n 's/^FMAPI_HOST="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true
      if [[ -z "$CFG_HOST" ]]; then CFG_HOST=$(sed -n 's/^HOST="\(.*\)"/\1/p' "$helper" 2>/dev/null | head -1) || true; fi
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
  http_code=$(curl -fsSL --max-time 30 -w '%{http_code}' -o "$tmp_config" "$url" 2>/dev/null) || {
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
