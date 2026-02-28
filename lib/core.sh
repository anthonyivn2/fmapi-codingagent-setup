#!/bin/bash
# lib/core.sh — Preamble, colors, logging, and utilities
# Sourced by setup-fmapi-claudecode.sh; do not run directly.

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

# Respect NO_COLOR (https://no-color.org) and non-TTY output
if [[ ! -t 1 ]] || [[ -n "${NO_COLOR:-}" ]]; then
  BOLD='' DIM='' RED='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

_OS_TYPE="$(uname -s 2>/dev/null || echo 'Unknown')"

VERBOSITY=1  # 0=quiet, 1=normal, 2=verbose
DRY_RUN=false

# ── Version ──────────────────────────────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
  FMAPI_VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION")"
else
  FMAPI_VERSION="dev"
fi

info()    { [[ "$VERBOSITY" -ge 1 ]] && echo -e "  ${CYAN}::${RESET} $1" || true; }
success() { [[ "$VERBOSITY" -ge 1 ]] && echo -e "  ${GREEN}${BOLD}ok${RESET} $1" || true; }
warn()    { [[ "$VERBOSITY" -ge 1 ]] && echo -e "  ${YELLOW}${BOLD}⚠ ${RESET}${YELLOW}$1${RESET}" || true; }
error()   { echo -e "\n  ${RED}${BOLD}!! ERROR${RESET}${RED} $1${RESET}\n" >&2; }
debug()   { [[ "$VERBOSITY" -ge 2 ]] && echo -e "  ${DIM}[debug]${RESET} $1" || true; }

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

# Reject dangerous base paths for settings file placement.
_validate_settings_path() {
  local p="$1"
  case "$p" in
    /|/bin|/sbin|/usr|/usr/*|/etc|/etc/*|/var|/tmp|/dev|/proc|/sys)
      error "Refusing to use system path as settings location: $p"
      exit 1 ;;
  esac
}

# Require a command or exit with an error message
require_cmd() {
  local cmd="$1" msg="$2"
  command -v "$cmd" &>/dev/null || { error "$msg"; exit 1; }
}

# Platform-appropriate install hint for a dependency
_install_hint() {
  local cmd="$1"
  case "$cmd" in
    jq)
      if [[ "$_OS_TYPE" == "Linux" ]]; then
        echo "sudo apt-get install -y jq  (or sudo yum install -y jq)"
      else
        echo "brew install jq"
      fi
      ;;
    databricks)
      if [[ "$_OS_TYPE" == "Linux" ]]; then
        echo "curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh"
      else
        echo "brew tap databricks/tap && brew install databricks"
      fi
      ;;
    claude)
      echo "curl -fsSL https://claude.ai/install.sh | bash"
      ;;
    curl)
      if [[ "$_OS_TYPE" == "Linux" ]]; then
        echo "sudo apt-get install -y curl  (or sudo yum install -y curl)"
      else
        echo "brew install curl"
      fi
      ;;
    *)
      echo "Install $cmd"
      ;;
  esac
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
