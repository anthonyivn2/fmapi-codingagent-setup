---
name: fmapi-codingagent-setup
description: Configure Claude Code to use Databricks Foundation Model API — interactive or non-interactive setup
user_invocable: true
---

# FMAPI Setup

Configure Claude Code to use Databricks Foundation Model API (FMAPI).

## Instructions

1. Determine the install path of this plugin. This SKILL.md file is located at `<install-path>/skills/fmapi-codingagent-setup/SKILL.md`, so the setup script is two directories up at `<install-path>/setup-fmapi-claudecode.sh`.

2. Ask the user how they want to run setup:

### Interactive mode (default)

Run with no arguments. The script will prompt for all required values, pre-populating defaults from any existing configuration:

```bash
bash "<install-path>/setup-fmapi-claudecode.sh"
```

### Non-interactive mode

Pass `--host` to enable non-interactive mode. All other flags auto-default if omitted:

```bash
bash "<install-path>/setup-fmapi-claudecode.sh" \
  --host "https://my-workspace.cloud.databricks.com"
```

## Available CLI Flags

| Flag | Description | Example |
|---|---|---|
| `--host URL` | Databricks workspace URL | `--host https://my-workspace.cloud.databricks.com` |
| `--profile NAME` | Databricks CLI profile name | `--profile my-profile` |
| `--model MODEL` | Primary model (default: `databricks-claude-opus-4-6`) | `--model databricks-claude-opus-4-6` |
| `--opus MODEL` | Opus model | `--opus databricks-claude-opus-4-6` |
| `--sonnet MODEL` | Sonnet model | `--sonnet databricks-claude-sonnet-4-6` |
| `--haiku MODEL` | Haiku model | `--haiku databricks-claude-haiku-4-5` |
| `--ttl MINUTES` | Token refresh interval in minutes (default: `30`, max: `60`) | `--ttl 45` |
| `--settings-location PATH` | Where to write settings (`home`, `cwd`, or a custom path) | `--settings-location home` |
| `--config PATH` | Load configuration from a local JSON file | `--config ./my-config.json` |
| `--config-url URL` | Load configuration from a remote JSON URL (HTTPS only) | `--config-url https://example.com/cfg.json` |

When `--host`, `--config`, or `--config-url` is provided, the script runs non-interactively. Other flags auto-default if omitted (profile defaults to `fmapi-claudecode-profile`). CLI flags override config file values. `--config` and `--config-url` are mutually exclusive.

## Other Commands

| Flag | Description |
|---|---|
| `--status` | Check FMAPI configuration health (use `/fmapi-codingagent-status` instead) |
| `--reauth` | Re-authenticate OAuth session (use `/fmapi-codingagent-reauth` instead) |
| `--uninstall` | Remove all FMAPI artifacts |
| `-h`, `--help` | Show help message |
