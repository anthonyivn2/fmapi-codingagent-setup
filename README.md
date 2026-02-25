# Coding Agents with Databricks Foundation Model API

Set up coding agents to run against models served through [Databricks Foundation Model API (FMAPI)](https://docs.databricks.com/aws/en/machine-learning/foundation-model-apis). FMAPI provides a unified gateway for serving foundation models from your Databricks workspace, enabling coding agents to leverage enterprise-grade model serving with built-in governance, security, and observability.

## Supported Coding Agents

FMAPI supports various coding agents today. The table below breaks down the Coding Agents that Databricks Foundational Model API supports today, and the quickstart script you can use to set it up.

| Coding Agent | FMAPI Support | Setup Script |
|---|---|---|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Supported | `setup-fmapi-claudecode.sh` |
| [OpenAI Codex](https://openai.com/index/codex/) | Supported | Script not yet available |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | Supported | Script not yet available |

## Claude Code

### Prerequisites

- **macOS** with `zsh` or `bash`
- [Homebrew](https://brew.sh/) (`brew`)
- [`jq`](https://jqlang.github.io/jq/) (install with `brew install jq`)
- A Databricks workspace with FMAPI enabled

### Quick Start

```bash
bash setup-fmapi-claudecode.sh
```

The script will prompt you for:

| Prompt | Type | Description |
|---|---|---|
| **Workspace URL** | Text input | Your Databricks workspace URL (e.g. `https://my-workspace.cloud.databricks.com`) |
| **CLI profile name** | Text input | Name for the Databricks CLI authentication profile (e.g. `my-profile`) |
| **Model** | Text input | The primary model to use. Defaults to `databricks-claude-opus-4-6` |
| **Opus model** | Text input | The Opus model for complex tasks. Defaults to `databricks-claude-opus-4-6` |
| **Sonnet model** | Text input | The Sonnet model for lighter tasks. Defaults to `databricks-claude-sonnet-4-6` |
| **Haiku model** | Text input | The Haiku model for fast, low-cost tasks. Defaults to `databricks-claude-haiku-4-5` |
| **Settings location** | Arrow-key selector | Where to write the `.claude/settings.json` file (home directory, current directory, or a custom path) |

> The **Settings location** prompt uses an interactive arrow-key selector &mdash; use the up/down arrow keys to navigate and Enter to confirm.

When re-running the script, existing configuration values are shown as defaults in `[brackets]` &mdash; press Enter to keep the current value.

Once complete, run:

```bash
claude
```

### Non-Interactive Setup

You can skip interactive prompts by passing CLI flags:

```bash
bash setup-fmapi-claudecode.sh \
  --host https://my-workspace.cloud.databricks.com \
  --profile my-profile
```

Any flags not provided will be prompted interactively. See [CLI Reference](#cli-reference) for all available flags.

### Plugin Skills

The setup script automatically registers this repo as a Claude Code plugin, making the following slash commands available inside Claude Code:

| Skill | Description |
|---|---|
| `/fmapi-codingagent-status` | Check FMAPI configuration health &mdash; OAuth session, workspace, and model settings |
| `/fmapi-codingagent-reauth` | Re-authenticate the Databricks OAuth session |
| `/fmapi-codingagent-setup` | Run full FMAPI setup (interactive or non-interactive with CLI flags) |

These skills allow you to manage your FMAPI configuration without leaving Claude Code.

### Status Dashboard

Check the health of your FMAPI configuration:

```bash
bash setup-fmapi-claudecode.sh --status
```

The dashboard shows:

- **Configuration** &mdash; Workspace URL, profile, and model names
- **Auth** &mdash; Whether the Databricks OAuth session is active or expired
- **File locations** &mdash; Paths to settings and helper files

### Re-authentication

Re-authenticate your Databricks OAuth session:

```bash
bash setup-fmapi-claudecode.sh --reauth
```

This triggers `databricks auth login` for your configured profile and verifies the new session is valid.

### CLI Reference

```
Usage: bash setup-fmapi-claudecode.sh [OPTIONS]

Commands:
  --status              Show FMAPI configuration health dashboard
  --reauth              Re-authenticate Databricks OAuth session
  --uninstall           Remove FMAPI helper scripts and settings
  -h, --help            Show this help message

Setup options (skip interactive prompts):
  --host URL            Databricks workspace URL
  --profile NAME        Databricks CLI profile name
  --model MODEL         Primary model (default: databricks-claude-opus-4-6)
  --opus MODEL          Opus model (default: databricks-claude-opus-4-6)
  --sonnet MODEL        Sonnet model (default: databricks-claude-sonnet-4-6)
  --haiku MODEL         Haiku model (default: databricks-claude-haiku-4-5)
  --ttl MINUTES         Token refresh interval in minutes (default: 30, max: 60)
  --settings-location PATH
                        Where to write settings: "home", "cwd", or a custom path
```

### What the Script Does

#### 1. Installs dependencies

- **Claude Code** &mdash; installed via `curl -fsSL https://claude.ai/install.sh | bash` if not already present.
- **Databricks CLI** &mdash; installed via Homebrew (`brew tap databricks/tap && brew install databricks`) if not already present.

#### 2. Authenticates with Databricks

Establishes an OAuth session using `databricks auth token --profile <profile>`. If no valid session exists, it triggers `databricks auth login` to start the OAuth flow in your browser. Any legacy FMAPI PATs from prior installations are automatically cleaned up.

#### 3. Writes `.claude/settings.json`

Creates or merges environment variables into your Claude Code settings file at the chosen location. The settings configure Claude Code to route API calls through your Databricks workspace:

| Setting | Location | Value |
|---|---|---|
| `apiKeyHelper` | Top-level | Path to `fmapi-key-helper.sh` (obtains OAuth tokens on demand) |
| `ANTHROPIC_MODEL` | `env` | Selected model (default: `databricks-claude-opus-4-6`) |
| `ANTHROPIC_BASE_URL` | `env` | `<workspace-url>/serving-endpoints/anthropic` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `env` | Selected Opus model (default: `databricks-claude-opus-4-6`) |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `env` | Selected Sonnet model (default: `databricks-claude-sonnet-4-6`) |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `env` | Selected Haiku model (default: `databricks-claude-haiku-4-5`) |
| `ANTHROPIC_CUSTOM_HEADERS` | `env` | `x-databricks-use-coding-agent-mode: true` |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | `env` | `1` |
| `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` | `env` | `1800000` (30 minutes &mdash; tokens refreshed before 1-hour OAuth expiry; configurable via `--ttl`) |

If the settings file already exists, the script merges the new values into it without overwriting other settings.

#### 4. Creates an API key helper script

Writes `fmapi-key-helper.sh` alongside `settings.json`. This script is invoked automatically by Claude Code via the [`apiKeyHelper`](https://docs.anthropic.com/en/docs/claude-code/settings#available-settings) setting to obtain OAuth access tokens on demand. The Databricks CLI handles token refresh transparently using stored refresh tokens.

### Security

The generated helper script and settings file are restricted to owner-only permissions. OAuth tokens are obtained on demand from the Databricks CLI and are not cached in any additional files.

### How Token Management Works

Claude Code invokes the helper script every 30 minutes by default (configurable via `--ttl` at setup time, max 60 minutes). The helper calls `databricks auth token` which returns the current OAuth access token, automatically refreshing it if needed using the stored refresh token. If the refresh token has expired (due to extended inactivity), the helper falls back to `databricks auth login` to trigger browser-based re-authentication.

### Available Models

Models available through FMAPI depend on what is enabled in your Databricks workspace. The setup script supports:

| Model ID | Description |
|---|---|
| `databricks-claude-opus-4-6` | Claude Opus 4.6 (default) |
| `databricks-claude-sonnet-4-6` | Claude Sonnet 4.6 (default Sonnet) |
| `databricks-claude-sonnet-4-5` | Claude Sonnet 4.5 |
| `databricks-claude-haiku-4-5` | Claude Haiku 4.5 (default Haiku) |

### Uninstalling

To remove all FMAPI artifacts created by the setup script:

```bash
bash setup-fmapi-claudecode.sh --uninstall
```

The uninstall process:

1. **Discovers artifacts** &mdash; Finds helper scripts and settings files with FMAPI keys.
2. **Deletes helper script** &mdash; Removes `fmapi-key-helper.sh` and any legacy cache files.
3. **Cleans settings files** &mdash; Removes FMAPI-specific keys (`apiKeyHelper`, `ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL`, etc.) from `.claude/settings.json`. If no other settings remain, the file is deleted. Non-FMAPI settings are preserved.
4. **Removes plugin registration** &mdash; Deregisters the plugin from `~/.claude/plugins/installed_plugins.json`.

Re-running `--uninstall` when nothing is installed is safe and will print "Nothing to uninstall."

### Re-running the Script

You can safely re-run `setup-fmapi-claudecode.sh` at any time to:

- Update the workspace URL, profile, or models (Opus, Sonnet, Haiku)
- Repair a missing or corrupted settings file or helper script

When re-running, existing configuration values are discovered from the current settings and shown as defaults. Press Enter to keep any current value, or type a new value to change it.

The script will overwrite the existing helper script and merge settings without duplication.

### Troubleshooting

**"Workspace URL must start with https://"**
Provide the full URL including the scheme, e.g. `https://my-workspace.cloud.databricks.com`.

**"apiKeyHelper failed" or authentication errors**
Run the helper script manually to diagnose: `sh ~/.claude/fmapi-key-helper.sh`. If it prints an OAuth error, re-authenticate with `databricks auth login --host <workspace-url> --profile <profile>`, or use `/fmapi-codingagent-reauth` inside Claude Code.

**Claude Code returns authentication errors**
Your OAuth session may have expired. Run `databricks auth login --host <workspace-url> --profile <profile>` to refresh the session, then retry `claude`.

## OpenAI Codex

FMAPI supports OpenAI Codex today. A setup script for this repo is not yet available &mdash; contributions welcome.

## Gemini CLI

FMAPI supports Gemini CLI today. A setup script for this repo is not yet available &mdash; contributions welcome.
