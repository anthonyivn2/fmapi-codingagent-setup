#!/bin/bash
# lib/help.sh — Help text
# Sourced by setup-fmapi-claudecode.sh; do not run directly.

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
  --self-update         Update to the latest version
  --uninstall           Remove FMAPI helper scripts and settings
  -h, --help            Show this help message

Setup options (skip interactive prompts):
  --host URL            Databricks workspace URL (required for non-interactive)
  --profile NAME        CLI profile name (default: fmapi-claudecode-profile)
  --model MODEL         Primary model (default: databricks-claude-opus-4-6)
  --opus MODEL          Opus model (default: databricks-claude-opus-4-6)
  --sonnet MODEL        Sonnet model (default: databricks-claude-sonnet-4-6)
  --haiku MODEL         Haiku model (default: databricks-claude-haiku-4-5)
  --ttl MINUTES         Token refresh interval in minutes (default: 5, max: 60)
  --settings-location   Where to write settings: "home", "cwd", or path (default: home)

Config file options:
  --config PATH         Load configuration from a local JSON file
  --config-url URL      Load configuration from a remote JSON URL (HTTPS only)

Output options:
  --verbose             Show debug-level output
  --quiet, -q           Suppress informational output (errors always shown)
  --no-color            Disable colored output (also respects NO_COLOR env var)
  --dry-run             Show what would happen without making changes

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

  # Update to the latest version
  bash setup-fmapi-claudecode.sh --self-update

  # Preview what setup would do (no changes made)
  bash setup-fmapi-claudecode.sh --dry-run --host https://my-workspace.cloud.databricks.com

  # Verbose output for debugging
  bash setup-fmapi-claudecode.sh --verbose --status

  # Quiet mode for CI (errors only)
  bash setup-fmapi-claudecode.sh --quiet --host https://my-workspace.cloud.databricks.com

  # Pipe-friendly (no ANSI codes)
  bash setup-fmapi-claudecode.sh --no-color --status

  # Uninstall all FMAPI artifacts
  bash setup-fmapi-claudecode.sh --uninstall

Troubleshooting:
  OAuth expired        Run: bash setup-fmapi-claudecode.sh --reauth
  ConnectionRefused    Run: bash setup-fmapi-claudecode.sh --reinstall
  "No config found"    Run setup first (without --status/--reauth)
  Wrong workspace URL  URL must start with https:// and have no trailing slash
  Permission denied    Helper script needs execute permission (chmod 700)
  Model not found      Run: bash setup-fmapi-claudecode.sh --list-models
  Update available     Run: bash setup-fmapi-claudecode.sh --self-update
  Unclear issue        Run: bash setup-fmapi-claudecode.sh --doctor
HELPTEXT
  exit 0
}
