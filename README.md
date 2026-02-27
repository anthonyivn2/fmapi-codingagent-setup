# Coding Agents with Databricks Foundation Model API

[Databricks Foundation Model API (FMAPI)](https://docs.databricks.com/aws/en/machine-learning/foundation-model-apis) gives Databricks users access to both frontier and open-source LLMs, served directly from your workspace with built-in governance and security.

## What You Get

- **Leverage Popular Coding Agents against models hosted in your Databricks workspace** &mdash; route all API calls through Databricks Foundation Model API
- **One-command setup** &mdash; installs dependencies, authenticates via OAuth, and configures everything
- **Automatic OAuth token management** &mdash; no PATs to rotate or manage
- **Built-in diagnostics and model validation** &mdash; `--doctor`, `--list-models`, `--validate-models`
- **Plugin slash commands** &mdash; manage your FMAPI config without leaving Claude Code
- **Built-in Usage Tracking and Payload Logging through Databricks AI Gateway** &mdash; Leverage Databricks's [AI Gateway Usage Tracking](https://docs.databricks.com/aws/en/ai-gateway/configure-ai-gateway-endpoints#configure-ai-gateway-using-the-ui) to track and audit Coding Agent usage for your organization, and track your Coding Agent request and response payload through the use of [AI Gateway Inference Table](https://docs.databricks.com/aws/en/ai-gateway/inference-tables)


> *This repo is built and maintained with the help of coding agents running with Databricks Foundation Model API. We dogfood our own products around here*

## Supported Agents

FMAPI supports all of the coding agents listed below. Setup scripts automate the configuration for each agent &mdash; scripts for OpenAI Codex and Gemini CLI are planned.

| Coding Agent | Setup Script | Status |
|---|---|---|
| Claude Code | `setup-fmapi-claudecode.sh` | Implemented |
| OpenAI Codex | — | Setup script planned |
| Gemini CLI | — | Setup script planned |

## Claude Code

**Prerequisites:** macOS or Linux, and a Databricks workspace with FMAPI enabled. Everything else is installed automatically. Windows is not currently supported.

### Install

Install with a single command:

```bash
bash <(curl -sL https://raw.githubusercontent.com/anthonyivn2/fmapi-codingagent-setup/main/install.sh)
```

This clones the repo to `~/.fmapi-codingagent-setup/`. To install to a custom location, set `FMAPI_HOME`:

```bash
FMAPI_HOME=~/my-custom-path bash <(curl -sL https://raw.githubusercontent.com/anthonyivn2/fmapi-codingagent-setup/main/install.sh)
```

Then run setup:

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh
```

The script walks you through setup interactively: it asks for your Databricks workspace URL, a CLI profile name, which models to use (Opus, Sonnet, Haiku), and where to write the settings file. Sensible defaults are provided for everything except the workspace URL.

Once complete you can proceed to run Claude Code as per usual:

```bash
claude
```

<details>
<summary><strong>Install from Source</strong></summary>

Clone the repo manually to any location:

```bash
git clone https://github.com/anthonyivn2/fmapi-codingagent-setup.git
cd fmapi-codingagent-setup
bash setup-fmapi-claudecode.sh
```

If you install from source, replace `~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh` in the examples below with the path to your clone.

</details>

### What the Script Does

1. **Installs dependencies** &mdash; Claude Code, Databricks CLI, and jq. Skips anything already installed. Uses Homebrew on macOS, `apt-get`/`yum` and curl installers on Linux.

2. **Authenticates with Databricks** &mdash; Establishes an OAuth session using `databricks auth token`. If no valid session exists, it opens your browser for OAuth login. Legacy PATs from prior installations are cleaned up automatically.

3. **Writes `.claude/settings.json`** &mdash; Configures Claude Code to route API calls through your Databricks workspace, including model selection and the path to the token helper. If the file already exists, new values are merged in without overwriting other settings.

4. **Creates an API key helper script** &mdash; Writes `fmapi-key-helper.sh` alongside the settings file. Claude Code invokes this automatically via the [`apiKeyHelper`](https://docs.anthropic.com/en/docs/claude-code/settings#available-settings) setting to obtain OAuth access tokens on demand.

### Managing Your Setup

#### Status Dashboard

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --status
```

- **Configuration** &mdash; workspace URL, profile, and model names
- **Auth** &mdash; whether the OAuth session is active or expired
- **File locations** &mdash; paths to settings and helper files

#### Re-authentication

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --reauth
```

Triggers `databricks auth login` for your configured profile and verifies the new session is valid.

#### Diagnostics

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --doctor
```

Runs six categories of checks, each reporting **PASS**, **FAIL**, **WARN**, or **SKIP** with actionable fix suggestions:

- **Dependencies** &mdash; jq, databricks, claude, and curl are installed; reports versions
- **Configuration** &mdash; settings file is valid JSON, all required FMAPI keys present, helper script exists and is executable
- **Profile** &mdash; Databricks CLI profile exists in `~/.databrickscfg`
- **Auth** &mdash; OAuth token is valid
- **Connectivity** &mdash; HTTP reachability to the Databricks serving endpoints API
- **Models** &mdash; all configured model names exist as endpoints and are READY

Exits with code 1 if any checks fail.

#### Model Management

List all serving endpoints in your workspace:

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --list-models
```

Currently configured models are highlighted in green. Use this to discover available model IDs when running setup.

Validate that your configured models exist and are ready:

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --validate-models
```

Reports per-model status: **PASS** (exists and READY), **WARN** (exists but not READY), **FAIL** (not found), or **SKIP** (not configured). Exits with code 1 if any models fail validation.

#### Re-running the Script

You can safely re-run the setup script at any time to update the workspace URL, profile, or models, or to repair a missing or corrupted settings file. Existing values are shown as defaults &mdash; press Enter to keep them.

For a fully non-interactive re-run using your previously saved configuration:

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --reinstall
```

#### Uninstalling

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --uninstall
```

The uninstall command removes all FMAPI artifacts in order:

1. **Helper scripts** &mdash; deletes `fmapi-key-helper.sh` and any legacy `.fmapi-pat-cache` files
2. **Settings** &mdash; removes FMAPI-specific keys (`apiKeyHelper`, `ANTHROPIC_*`, etc.) from `.claude/settings.json`. Non-FMAPI settings are preserved; if no other settings remain, the file is deleted entirely
3. **Plugin registration** &mdash; deregisters `fmapi-codingagent` from `~/.claude/plugins/installed_plugins.json`
4. **Install directory** &mdash; removes `~/.fmapi-codingagent-setup/` (the default location created by `install.sh`)

Before removing anything, the script lists all discovered artifacts and asks for confirmation. Re-running `--uninstall` when nothing is installed is safe &mdash; it reports "Nothing to uninstall" and exits.

##### Manual Cleanup

If you installed to a custom location using `FMAPI_HOME`, the uninstall command only removes the default path. Delete your custom install directory manually:

```bash
rm -rf /path/to/your/custom/install
```

To fully clean up all possible FMAPI-related paths by hand (e.g. if the setup script is already gone):

```bash
# Remove the install directory (default location)
rm -rf ~/.fmapi-codingagent-setup

# Remove the helper script (default location)
rm -f ~/.claude/fmapi-key-helper.sh

# Remove FMAPI plugin registration (edit or delete)
# If fmapi-codingagent is the only plugin:
rm -f ~/.claude/plugins/installed_plugins.json
# Otherwise, remove the "fmapi-codingagent" key from the JSON file

# Remove FMAPI keys from settings (edit or delete)
# If FMAPI is the only config in ~/.claude/settings.json:
rm -f ~/.claude/settings.json
# Otherwise, remove apiKeyHelper and the ANTHROPIC_* / CLAUDE_CODE_* env keys from the JSON file
```

#### Updating

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --self-update
```

Fetches the latest changes from the remote repository and updates in place. Shows how many commits are new and reports the version change. Requires the installation to be a git clone (both the quick installer and manual clone work).

### Plugin Skills

The setup script registers this repo as a Claude Code plugin, making these slash commands available:

| Skill | Description |
|---|---|
| `/fmapi-codingagent-status` | Check FMAPI configuration health &mdash; OAuth session, workspace, and model settings |
| `/fmapi-codingagent-reauth` | Re-authenticate the Databricks OAuth session |
| `/fmapi-codingagent-setup` | Run full FMAPI setup (interactive or non-interactive with CLI flags) |
| `/fmapi-codingagent-doctor` | Run comprehensive diagnostics (dependencies, config, auth, connectivity, models) |
| `/fmapi-codingagent-list-models` | List all serving endpoints available in the workspace |
| `/fmapi-codingagent-validate-models` | Validate that configured models exist and are ready |

### Advanced Setup

#### Non-Interactive Setup

Pass `--host` to enable non-interactive mode. All other flags auto-default if omitted:

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh \
  --host https://my-workspace.cloud.databricks.com
```

Override any default with additional flags &mdash; see [CLI Reference](#cli-reference) for the full list.

#### Config File Setup

Load configuration from a JSON file instead of passing individual flags. Useful for teams standardizing setup across users.

```bash
# From a local config file
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --config ./my-config.json

# From a remote URL (HTTPS only)
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --config-url https://example.com/fmapi-config.json

# Config file with CLI overrides (CLI flags take priority)
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --config ./my-config.json --model databricks-claude-sonnet-4-6
```

Both `--config` and `--config-url` enable non-interactive mode. See [`example-config.json`](example-config.json) for the full format and all supported keys.

Priority when combining sources: CLI flags > config file > existing `settings.json` > hardcoded defaults. If the config file is missing `host` and no `--host` flag is provided, the script errors out.

### CLI Reference

```
Usage: bash setup-fmapi-claudecode.sh [OPTIONS]

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
```

### How It Works

#### Token Management

Claude Code invokes the helper script every 5 minutes by default (configurable via `--ttl`, max 60 minutes). The helper calls `databricks auth token`, which returns the current OAuth access token and automatically refreshes it using the stored refresh token. If the refresh token has expired due to extended inactivity, the helper falls back to `databricks auth login` to trigger browser-based re-authentication.

### Troubleshooting

> **Not sure what's wrong?** Start with `bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --doctor`

**"Workspace URL must start with https://"**
Provide the full URL including the scheme, e.g. `https://my-workspace.cloud.databricks.com`.

**"apiKeyHelper failed" or authentication errors**
Run the helper script manually to diagnose: `sh ~/.claude/fmapi-key-helper.sh`. If it prints an OAuth error, re-authenticate with `bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --reauth` or use `/fmapi-codingagent-reauth` inside Claude Code.

**Claude Code returns authentication errors**
Your OAuth session may have expired. Run `bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --reauth` to refresh the session, then retry `claude`.

**Model not found or wrong model name**
Run `bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --list-models` to discover available serving endpoints, then re-run setup to pick the correct model IDs.

**Unclear issue**
Run `bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --doctor` for a comprehensive diagnostic report covering dependencies, configuration, authentication, connectivity, and model validation.

## Other Agents

OpenAI Codex and Gemini CLI are planned &mdash; see the [Supported Agents](#supported-agents) table for current status. Contributions welcome.
