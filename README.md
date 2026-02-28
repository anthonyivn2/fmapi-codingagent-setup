# Coding Agents with Databricks Foundation Model API

Databricks serves frontier and open-source LLMs through its [Foundation Model API (FMAPI)](https://docs.databricks.com/aws/en/machine-learning/foundation-model-apis) — and those same models can power coding agents like Claude Code, OpenAI Codex, Gemini CLI, and many others! This repo automates the setup so you can point your favorite coding agent at your Databricks workspace with built-in governance, security, and usage tracking.

> *In case you are wondering, yes, this repo is built alongside coding agents powered by LLMs from Databricks Foundation Model API. We like to dogfood our own products.*

**Status: Experimental** — Currently handles FMAPI setup for coding agents. Considering expanding to cover AI Gateway policies, inference table configuration, and OTEL telemetry ingestion via [Databricks Zerobus](https://docs.databricks.com/aws/en/ingestion/zerobus-overview). Feedback and ideas are welcomed — open an issue or reach out!

## What You Get

- **Leverage Popular Coding Agents against models hosted in your Databricks workspace** &mdash; route all API calls through Databricks Foundation Model API
- **One-command setup** &mdash; installs dependencies, authenticates via OAuth, and configures everything
- **Automatic OAuth token management** &mdash; no PATs to rotate or manage
- **Built-in diagnostics and model validation** &mdash; `--doctor`, `--list-models`, `--validate-models`
- **Plugin slash commands** &mdash; manage your FMAPI config without leaving Claude Code
- **Built-in Usage Tracking and Payload Logging through Databricks AI Gateway** &mdash; Leverage Databricks's [AI Gateway Usage Tracking](https://docs.databricks.com/aws/en/ai-gateway/configure-ai-gateway-endpoints#configure-ai-gateway-using-the-ui) to track and audit Coding Agent usage for your organization, and track your Coding Agent request and response payload through the use of [AI Gateway Inference Table](https://docs.databricks.com/aws/en/ai-gateway/inference-tables)

## Supported Agents

FMAPI supports all of the coding agents listed below. Setup scripts automate the configuration for each agent &mdash; scripts for OpenAI Codex and Gemini CLI are planned.

| Coding Agent | Setup Script | Status |
|---|---|---|
| Claude Code | `setup-fmapi-claudecode.sh` | Implemented |
| OpenAI Codex | — | Setup script planned |
| Gemini CLI | — | Setup script planned |

## Claude Code

**Prerequisites:** macOS, Linux, or WSL (Windows Subsystem for Linux; experimental), and a Databricks workspace with FMAPI enabled. Everything else is installed automatically.

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

<details>
<summary><strong>Express One-Step Install + Setup</strong></summary>
Use `--agent` to install and launch setup in a single command. Any additional flags are forwarded to the setup script:

```bash
# Interactive setup
bash <(curl -sL https://raw.githubusercontent.com/anthonyivn2/fmapi-codingagent-setup/main/install.sh) \
  --agent claude-code

# Non-interactive setup
bash <(curl -sL https://raw.githubusercontent.com/anthonyivn2/fmapi-codingagent-setup/main/install.sh) \
  --agent claude-code --host https://my-workspace.cloud.databricks.com
```

The `--agent` flag accepts agent names like `claude-code` (hyphens are normalized automatically). If the agent name doesn't match any setup script, the installer lists available agents.

</details><br>

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

<details>
<summary><strong>WSL (Windows) Notes — Experimental</strong></summary>

WSL 1 and WSL 2 are both supported. WSL support is **experimental** — it has not yet been validated on real WSL environments. Please report any issues. The setup script auto-detects WSL and handles browser-based OAuth authentication.

If the browser does not open automatically during OAuth login:

1. **Install `wslu`** (recommended): `sudo apt-get install -y wslu` — provides `wslview` for opening URLs from WSL in your Windows browser.
2. **Or set the `BROWSER` variable**: `export BROWSER='powershell.exe /c start'`

WSL 2 with WSLg (GUI support) typically works without extra configuration.

Run `--doctor` to verify your WSL environment:

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --doctor
```

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

You can safely re-run the setup script at any time to update the workspace URL, profile, or models, or to repair a missing or corrupted settings file.

When you re-run setup interactively with an existing configuration, the script shows a summary of your current settings and asks whether to keep them or reconfigure:

```
  Existing configuration found:

  Workspace  https://my-workspace.cloud.databricks.com
  Profile    profile-name
  TTL        ...
  Model      ...
  Opus       ...
  Sonnet     ...
  Haiku      ...
  Settings   ...

  ? Keep this configuration?
  ❯ Yes, proceed    re-run setup with existing config
    No, reconfigure start fresh with all prompts
```

Selecting **Yes, proceed** re-runs the full setup (dependencies, auth, settings, smoke test) without prompting for each value. Selecting **No, reconfigure** shows all prompts with your existing values as defaults. First-time users (no existing config) see the normal prompt flow.

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

Re-running the installer (`bash <(curl ...) install.sh`) also works for updating. It shows a before/after version comparison:

```
  ok Updated from v1.0.0 → v1.1.0.
```

Or if already current:

```
  ok Already up to date at v1.1.0.
```

When updating an existing install that already has FMAPI configured, the installer prints a `--reinstall` hint so you can quickly refresh your setup with the latest script version.

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

#### AI Gateway v2 (Beta)

Route API calls through Databricks AI Gateway v2 instead of the default serving endpoints. AI Gateway v2 uses a dedicated endpoint format (`https://<workspace-id>.ai-gateway.cloud.databricks.com/anthropic`) and may offer additional gateway features.

```bash
# Auto-detect workspace ID
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh \
  --host https://my-workspace.cloud.databricks.com --ai-gateway

# Explicit workspace ID
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh \
  --host https://my-workspace.cloud.databricks.com --ai-gateway --workspace-id 1234567890
```

In interactive mode, the script prompts you to choose between "Serving Endpoints (default)" and "AI Gateway v2 (beta)". When AI Gateway is selected, the workspace ID is auto-detected from the Databricks API. If auto-detection fails, you are prompted to enter it manually (or use `--workspace-id` in non-interactive mode).

The `--ai-gateway` flag can also be set via config files using the `"ai_gateway": true` key alongside an optional `"workspace_id"` value. See [`example-config.json`](example-config.json).

**Note:** AI Gateway v2 is in beta. OAuth token management (`apiKeyHelper`) works the same way &mdash; only the base URL changes.

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
  --ttl MINUTES         Token refresh interval in minutes (default: 60, max: 60, 60 recommended)
  --settings-location   Where to write settings: "home", "cwd", or path (default: home)
  --ai-gateway          Use AI Gateway v2 for API routing (beta, default: off)
  --workspace-id ID     Databricks workspace ID for AI Gateway (auto-detected if omitted)

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

Claude Code invokes the helper script every 60 minutes by default (configurable via `--ttl`, max 60 minutes). The helper calls `databricks auth token`, which returns the current OAuth access token and automatically refreshes it using the stored refresh token. If the refresh token has expired due to extended inactivity, the helper falls back to `databricks auth login` to trigger browser-based re-authentication. Values under 15 minutes are not recommended as they may cause failures during long-running subagent calls.

### Troubleshooting

> **Not sure what's wrong?** Run `--doctor` first &mdash; it checks dependencies, config files, auth, connectivity, and models in one pass:
> ```bash
> bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --doctor
> ```

---

#### "Workspace URL must start with https://"

The script requires the full URL with scheme. Use the format:

```
https://my-workspace.cloud.databricks.com
```

Do not include a trailing slash or path segments.

---

#### "apiKeyHelper failed" or token errors in Claude Code

This means the helper script that supplies OAuth tokens is failing. To diagnose:

1. Run the helper directly and check its output:
   ```bash
   sh ~/.claude/fmapi-key-helper.sh
   ```
2. If it prints an error about an expired or invalid token, re-authenticate:
   ```bash
   bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --reauth
   ```
   Or use `/fmapi-codingagent-reauth` inside Claude Code.
3. If the helper script is missing or not executable, re-run setup to regenerate it:
   ```bash
   bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --reinstall
   ```

---

#### Claude Code returns "authentication failed" or 401 errors

Your OAuth session has likely expired. OAuth sessions expire after a period of inactivity.

1. Re-authenticate:
   ```bash
   bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --reauth
   ```
2. Verify the session is now valid:
   ```bash
   bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --status
   ```
3. Restart Claude Code:
   ```bash
   claude
   ```

---

#### Model not found or "endpoint does not exist"

The configured model name does not match any serving endpoint in your workspace.

1. List available endpoints to find the correct name:
   ```bash
   bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --list-models
   ```
2. Re-run setup and select the correct model IDs:
   ```bash
   bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh
   ```

---

#### Claude Code starts but responses are slow or time out

This is usually a serving endpoint issue, not a setup issue. Check that your endpoints are in READY state:

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --validate-models
```

If any model shows **WARN** (exists but not READY), the endpoint may be provisioning or unhealthy. Check the endpoint status in your Databricks workspace UI.

---

#### Setup script says "databricks: command not found"

The Databricks CLI is not installed or not on your `PATH`. The setup script installs it automatically, but if that failed:

- **macOS:** `brew install databricks`
- **Linux:** `curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh`

Then re-run setup.

---

#### Still stuck?

If none of the above help, run a full diagnostic and review the output:

```bash
bash ~/.fmapi-codingagent-setup/setup-fmapi-claudecode.sh --doctor --verbose
```

The `--verbose` flag adds debug-level detail to every check. Look for any **FAIL** lines &mdash; each includes a suggested fix.

## Other Agents

OpenAI Codex and Gemini CLI are planned &mdash; see the [Supported Agents](#supported-agents) table for current status. Contributions welcome.
