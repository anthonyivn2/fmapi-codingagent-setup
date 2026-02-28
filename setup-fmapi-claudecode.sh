#!/bin/bash
set -euo pipefail
umask 077

# ── Script directory (used by all modules) ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source library modules ────────────────────────────────────────────────────
for _lib_file in "${SCRIPT_DIR}/lib/core.sh" "${SCRIPT_DIR}/lib/help.sh" \
                  "${SCRIPT_DIR}/lib/config.sh" "${SCRIPT_DIR}/lib/shared.sh" \
                  "${SCRIPT_DIR}/lib/commands.sh" "${SCRIPT_DIR}/lib/setup.sh"; do
  if [[ ! -f "$_lib_file" ]]; then
    echo "ERROR: Missing required file: ${_lib_file}" >&2
    echo "Run this script from the cloned repository." >&2
    exit 1
  fi
done

# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/lib/core.sh"
# shellcheck source=lib/help.sh
source "${SCRIPT_DIR}/lib/help.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/shared.sh
source "${SCRIPT_DIR}/lib/shared.sh"
# shellcheck source=lib/commands.sh
source "${SCRIPT_DIR}/lib/commands.sh"
# shellcheck source=lib/setup.sh
source "${SCRIPT_DIR}/lib/setup.sh"

# ── CLI flag parsing ──────────────────────────────────────────────────────────
CLI_HOST="" CLI_PROFILE="" CLI_MODEL="" CLI_OPUS="" CLI_SONNET="" CLI_HAIKU=""
CLI_TTL=""
CLI_SETTINGS_LOCATION=""
CLI_AI_GATEWAY="" CLI_WORKSPACE_ID=""
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
    --self-update)  ACTION="self-update"; shift ;;
    --no-color)     BOLD='' DIM='' RED='' GREEN='' YELLOW='' CYAN='' RESET=''; shift ;;
    --verbose)      VERBOSITY=2; shift ;;
    --quiet|-q)     VERBOSITY=0; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --host)         CLI_HOST="${2:-}"; if [[ -z "$CLI_HOST" ]]; then error "--host requires a URL."; exit 1; fi; shift 2 ;;
    --profile)      CLI_PROFILE="${2:-}"; if [[ -z "$CLI_PROFILE" ]]; then error "--profile requires a name."; exit 1; fi; shift 2 ;;
    --model)        CLI_MODEL="${2:-}"; if [[ -z "$CLI_MODEL" ]]; then error "--model requires a value."; exit 1; fi; shift 2 ;;
    --opus)         CLI_OPUS="${2:-}"; if [[ -z "$CLI_OPUS" ]]; then error "--opus requires a value."; exit 1; fi; shift 2 ;;
    --sonnet)       CLI_SONNET="${2:-}"; if [[ -z "$CLI_SONNET" ]]; then error "--sonnet requires a value."; exit 1; fi; shift 2 ;;
    --haiku)        CLI_HAIKU="${2:-}"; if [[ -z "$CLI_HAIKU" ]]; then error "--haiku requires a value."; exit 1; fi; shift 2 ;;
    --ttl)          CLI_TTL="${2:-}"; if [[ -z "$CLI_TTL" ]]; then error "--ttl requires a value."; exit 1; fi; shift 2 ;;
    --settings-location) CLI_SETTINGS_LOCATION="${2:-}"; if [[ -z "$CLI_SETTINGS_LOCATION" ]]; then error "--settings-location requires a value."; exit 1; fi; shift 2 ;;
    --config)       CLI_CONFIG_FILE="${2:-}"; if [[ -z "$CLI_CONFIG_FILE" ]]; then error "--config requires a file path."; exit 1; fi; shift 2 ;;
    --config-url)   CLI_CONFIG_URL="${2:-}"; if [[ -z "$CLI_CONFIG_URL" ]]; then error "--config-url requires a URL."; exit 1; fi; shift 2 ;;
    --ai-gateway)   CLI_AI_GATEWAY="true"; shift ;;
    --workspace-id) CLI_WORKSPACE_ID="${2:-}"; if [[ -z "$CLI_WORKSPACE_ID" ]]; then error "--workspace-id requires a value."; exit 1; fi; shift 2 ;;
    *)              error "Unknown option: $1"; echo "  Run with --help for usage." >&2; exit 1 ;;
  esac
done

# ── Mutual exclusion: --config and --config-url ──────────────────────────────
if [[ -n "$CLI_CONFIG_FILE" ]] && [[ -n "$CLI_CONFIG_URL" ]]; then
  error "Cannot use both --config and --config-url. Choose one."
  exit 1
fi

# ── --dry-run validation ─────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]] && [[ -n "$ACTION" ]]; then
  error "--dry-run cannot be combined with --${ACTION}. It only applies to setup."
  exit 1
fi

# ── --workspace-id validation ────────────────────────────────────────────────
if [[ -n "$CLI_WORKSPACE_ID" ]]; then
  if ! [[ "$CLI_WORKSPACE_ID" =~ ^[0-9]+$ ]]; then
    error "--workspace-id must be numeric. Got: $CLI_WORKSPACE_ID"
    exit 1
  fi
  if [[ -z "$CLI_AI_GATEWAY" ]]; then
    error "--workspace-id requires --ai-gateway to be set."
    exit 1
  fi
fi

# ── Config file loading ──────────────────────────────────────────────────────
FILE_HOST="" FILE_PROFILE="" FILE_MODEL="" FILE_OPUS="" FILE_SONNET="" FILE_HAIKU=""
FILE_TTL="" FILE_SETTINGS_LOCATION=""
FILE_AI_GATEWAY="" FILE_WORKSPACE_ID=""

if [[ -n "$CLI_CONFIG_FILE" ]] || [[ -n "$CLI_CONFIG_URL" ]]; then
  require_cmd jq "jq is required to parse config files. Install with: $(_install_hint jq)"
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
[[ "$DRY_RUN" == true ]] && NON_INTERACTIVE=true

# ── --reinstall: rerun setup with previous config ─────────────────────────────
if [[ "${ACTION}" == "reinstall" ]]; then
  require_cmd jq "jq is required for reinstall. Install with: $(_install_hint jq)"
  discover_config
  if [[ "$CFG_FOUND" != true ]] || [[ -z "$CFG_HOST" ]]; then
    error "No existing FMAPI configuration found. Run setup first (without --reinstall)."
    exit 1
  fi
  info "Re-installing with existing config (${CFG_HOST}, profile: ${CFG_PROFILE:-fmapi-claudecode-profile})"
  NON_INTERACTIVE=true
  # Propagate gateway config from discovered config
  [[ -z "$CLI_AI_GATEWAY" ]] && CLI_AI_GATEWAY="${CFG_AI_GATEWAY:-false}"
  [[ -z "$CLI_WORKSPACE_ID" ]] && CLI_WORKSPACE_ID="${CFG_WORKSPACE_ID:-}"
fi

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${ACTION}" in
  status)          do_status; exit 0 ;;
  reauth)          do_reauth; exit 0 ;;
  doctor)          do_doctor; exit 0 ;;
  list-models)     do_list_models; exit 0 ;;
  validate-models) do_validate_models; exit 0 ;;
  uninstall)       do_uninstall; exit 0 ;;
  self-update)     do_self_update; exit 0 ;;
esac

do_setup
