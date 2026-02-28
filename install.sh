#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/anthonyivn2/fmapi-codingagent-setup.git"
INSTALL_DIR="${FMAPI_HOME:-${HOME}/.fmapi-codingagent-setup}"
BRANCH="main"
AGENT=""
SETUP_ARGS=()

# ── Colors (respect NO_COLOR) ────────────────────────────────────────────────
BOLD='\033[1m' DIM='\033[2m' GREEN='\033[32m' CYAN='\033[36m' RED='\033[31m' RESET='\033[0m'
if [[ ! -t 1 ]] || [[ -n "${NO_COLOR:-}" ]]; then
  BOLD='' DIM='' GREEN='' CYAN='' RED='' RESET=''
fi

info()    { echo -e "  ${CYAN}::${RESET} $1"; }
success() { echo -e "  ${GREEN}${BOLD}ok${RESET} $1"; }
error()   { echo -e "\n  ${RED}${BOLD}!! ERROR${RESET}${RED} $1${RESET}\n" >&2; }

# ── Helpers ──────────────────────────────────────────────────────────────────

# Map agent script suffix to friendly display name
_agent_display_name() {
  case "$1" in
    claudecode)  echo "Claude Code" ;;
    codex)       echo "OpenAI Codex" ;;
    gemini)      echo "Gemini CLI" ;;
    *)           echo "$1" ;;
  esac
}

# Detect existing FMAPI config in ~/.claude/settings.json
_has_fmapi_config() {
  local settings="$HOME/.claude/settings.json"
  [[ -f "$settings" ]] || return 1
  if command -v jq &>/dev/null; then
    local base_url=""
    base_url=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$settings" 2>/dev/null) || true
    [[ -n "$base_url" ]] && return 0
    return 1
  fi
  grep -q "ANTHROPIC_BASE_URL" "$settings" 2>/dev/null
}

# ── Parse flags ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; if [[ -z "$BRANCH" ]]; then error "--branch requires a value."; exit 1; fi; shift 2 ;;
    --agent)  AGENT="${2:-}"; if [[ -z "$AGENT" ]]; then error "--agent requires a name."; exit 1; fi; shift 2 ;;
    -h|--help)
      echo "Usage: bash <(curl -sL .../install.sh) [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --branch NAME   Git branch or tag to install (default: main)"
      echo "  --agent NAME    Auto-run setup for the given agent after install"
      echo "                  (e.g., claude-code). Remaining flags are forwarded."
      echo "  -h, --help      Show this help"
      echo ""
      echo "Environment variables:"
      echo "  FMAPI_HOME      Install location (default: ~/.fmapi-codingagent-setup)"
      exit 0 ;;
    *) SETUP_ARGS+=("$1"); shift ;;
  esac
done

# If extra flags were provided without --agent, error out
if [[ ${#SETUP_ARGS[@]} -gt 0 ]] && [[ -z "$AGENT" ]]; then
  error "Unrecognized flags: ${SETUP_ARGS[*]}. Use --agent NAME to forward flags to a setup script."
  exit 1
fi

# ── Require git ──────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  error "git is required but not installed."
  exit 1
fi

echo -e "\n${BOLD}  FMAPI Codingagent Setup — Installer${RESET}\n"

# ── Clone or update ──────────────────────────────────────────────────────────
IS_UPDATE=false
pre_version=""
post_version=""

if [[ -d "${INSTALL_DIR}/.git" ]]; then
  IS_UPDATE=true
  # Capture pre-update version
  if [[ -f "${INSTALL_DIR}/VERSION" ]]; then
    pre_version=$(tr -d '[:space:]' < "${INSTALL_DIR}/VERSION")
  fi

  info "Existing installation found at ${DIM}${INSTALL_DIR}${RESET}"
  info "Updating..."
  git -C "$INSTALL_DIR" fetch --quiet origin "$BRANCH"
  git -C "$INSTALL_DIR" checkout --quiet "$BRANCH"
  git -C "$INSTALL_DIR" pull --quiet origin "$BRANCH"

  # Capture post-update version
  if [[ -f "${INSTALL_DIR}/VERSION" ]]; then
    post_version=$(tr -d '[:space:]' < "${INSTALL_DIR}/VERSION")
  fi

  if [[ -n "$pre_version" && -n "$post_version" && "$pre_version" != "$post_version" ]]; then
    success "Updated from v${pre_version} → v${post_version}."
  else
    success "Already up to date at v${post_version:-${pre_version:-unknown}}."
  fi
else
  if [[ -d "$INSTALL_DIR" ]]; then
    error "${INSTALL_DIR} exists but is not a git repo. Remove it first or set FMAPI_HOME."
    exit 1
  fi
  info "Cloning to ${DIM}${INSTALL_DIR}${RESET}..."
  git clone --quiet --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
  success "Installed."
fi

# ── Verify ───────────────────────────────────────────────────────────────────
# Verify at least one setup script exists
setup_scripts=()
for script in "${INSTALL_DIR}"/setup-fmapi-*.sh; do
  [[ -f "$script" ]] && setup_scripts+=("$script")
done

if [[ ${#setup_scripts[@]} -eq 0 ]]; then
  error "Installation verification failed: no setup-fmapi-*.sh scripts found."
  exit 1
fi

local_version="unknown"
if [[ -f "${INSTALL_DIR}/VERSION" ]]; then
  local_version=$(tr -d '[:space:]' < "${INSTALL_DIR}/VERSION")
fi

# ── Auto-run agent setup if --agent was provided ─────────────────────────────
if [[ -n "$AGENT" ]]; then
  # Normalize: claude-code → claudecode
  agent_normalized="${AGENT//-/}"
  setup_script="${INSTALL_DIR}/setup-fmapi-${agent_normalized}.sh"

  if [[ ! -f "$setup_script" ]]; then
    error "No setup script for agent '${AGENT}' (expected: setup-fmapi-${agent_normalized}.sh)."
    echo -e "  Available agents:" >&2
    for s in "${setup_scripts[@]}"; do
      suffix="${s##*/setup-fmapi-}"
      suffix="${suffix%.sh}"
      echo -e "    --agent ${suffix}  ($(_agent_display_name "$suffix"))" >&2
    done
    echo "" >&2
    exit 1
  fi

  info "Running setup for $(_agent_display_name "$agent_normalized")..."
  exec bash "$setup_script" ${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}
fi

# ── Print next steps ─────────────────────────────────────────────────────────
echo ""
success "fmapi-codingagent-setup v${local_version} installed to ${INSTALL_DIR}"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"

for s in "${setup_scripts[@]}"; do
  suffix="${s##*/setup-fmapi-}"
  suffix="${suffix%.sh}"
  display_name="$(_agent_display_name "$suffix")"
  echo ""
  echo -e "  Run setup for ${display_name}:"
  echo -e "    ${CYAN}bash ${s}${RESET}"
done

echo ""
echo -e "  Run non-interactive setup (example):"
echo -e "    ${CYAN}bash ${setup_scripts[0]} --host https://your-workspace.cloud.databricks.com${RESET}"

echo ""
echo -e "  Update to the latest version:"
echo -e "    ${CYAN}bash ${setup_scripts[0]} --self-update${RESET}"

# ── Reinstall hint (update + existing config) ─────────────────────────────────
if [[ "$IS_UPDATE" == true ]] && _has_fmapi_config; then
  echo ""
  echo -e "  ${BOLD}Already configured?${RESET} Update your setup with:"
  for s in "${setup_scripts[@]}"; do
    echo -e "    ${CYAN}bash ${s} --reinstall${RESET}"
  done
fi

echo ""
