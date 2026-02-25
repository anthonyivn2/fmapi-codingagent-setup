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

Pass all required values as CLI flags to skip prompts entirely:

```bash
bash "<install-path>/setup-fmapi-claudecode.sh" \
  --host "https://my-workspace.cloud.databricks.com" \
  --profile "my-profile"
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

When `--host` and `--profile` are both provided along with all other flags, the script runs non-interactively. Any missing flags will be prompted interactively, with existing config values shown as defaults.

## Other Commands

| Flag | Description |
|---|---|
| `--status` | Check FMAPI configuration health (use `/fmapi-codingagent-status` instead) |
| `--reauth` | Re-authenticate OAuth session (use `/fmapi-codingagent-reauth` instead) |
| `--uninstall` | Remove all FMAPI artifacts |
| `-h`, `--help` | Show help message |
