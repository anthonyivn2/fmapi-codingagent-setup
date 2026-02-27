#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/anthonyivn2/fmapi-codingagent-setup.git"
INSTALL_DIR="${FMAPI_HOME:-${HOME}/.fmapi-codingagent-setup}"
BRANCH="main"

# ── Colors (respect NO_COLOR) ────────────────────────────────────────────────
BOLD='\033[1m' DIM='\033[2m' GREEN='\033[32m' CYAN='\033[36m' RED='\033[31m' RESET='\033[0m'
if [[ ! -t 1 ]] || [[ -n "${NO_COLOR:-}" ]]; then
  BOLD='' DIM='' GREEN='' CYAN='' RED='' RESET=''
fi

info()    { echo -e "  ${CYAN}::${RESET} $1"; }
success() { echo -e "  ${GREEN}${BOLD}ok${RESET} $1"; }
error()   { echo -e "\n  ${RED}${BOLD}!! ERROR${RESET}${RED} $1${RESET}\n" >&2; }

# ── Parse flags ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; if [[ -z "$BRANCH" ]]; then error "--branch requires a value."; exit 1; fi; shift 2 ;;
    -h|--help)
      echo "Usage: bash <(curl -sL .../install.sh) [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --branch NAME   Git branch or tag to install (default: main)"
      echo "  -h, --help      Show this help"
      echo ""
      echo "Environment variables:"
      echo "  FMAPI_HOME      Install location (default: ~/.fmapi-codingagent-setup)"
      exit 0 ;;
    *) error "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Require git ──────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  error "git is required but not installed."
  exit 1
fi

echo -e "\n${BOLD}  FMAPI Codingagent Setup — Installer${RESET}\n"

# ── Clone or update ──────────────────────────────────────────────────────────
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  info "Existing installation found at ${DIM}${INSTALL_DIR}${RESET}"
  info "Updating..."
  git -C "$INSTALL_DIR" fetch --quiet origin "$BRANCH"
  git -C "$INSTALL_DIR" checkout --quiet "$BRANCH"
  git -C "$INSTALL_DIR" pull --quiet origin "$BRANCH"
  success "Updated to latest."
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
if [[ ! -f "${INSTALL_DIR}/setup-fmapi-claudecode.sh" ]]; then
  error "Installation verification failed: setup-fmapi-claudecode.sh not found."
  exit 1
fi

local_version="unknown"
if [[ -f "${INSTALL_DIR}/VERSION" ]]; then
  local_version=$(tr -d '[:space:]' < "${INSTALL_DIR}/VERSION")
fi

# ── Print next steps ─────────────────────────────────────────────────────────
echo ""
success "fmapi-codingagent-setup v${local_version} installed to ${INSTALL_DIR}"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo ""
echo -e "  Run setup for Claude Code:"
echo -e "    ${CYAN}bash ${INSTALL_DIR}/setup-fmapi-claudecode.sh${RESET}"
echo ""
echo -e "  Run non-interactive setup for Claude Code:"
echo -e "    ${CYAN}bash ${INSTALL_DIR}/setup-fmapi-claudecode.sh --host https://your-workspace.cloud.databricks.com${RESET}"
echo ""
echo -e "  Update Claude Code setup to the latest version:"
echo -e "    ${CYAN}bash ${INSTALL_DIR}/setup-fmapi-claudecode.sh --self-update${RESET}"
echo ""
