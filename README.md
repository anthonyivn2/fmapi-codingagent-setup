# Claude Code using Databricks Foundational Model API

Set up [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to run against the Anthropic models served through [Databricks Foundation Model API (FMAPI)](https://docs.databricks.com/en/machine-learning/foundation-models/index.html) in a single command.

## Prerequisites

- **macOS** with `zsh` or `bash`
- [Homebrew](https://brew.sh/) (`brew`)
- [`jq`](https://jqlang.github.io/jq/) (install with `brew install jq`)
- A Databricks workspace with FMAPI enabled

## Quick Start

```bash
lets bash setup-fmapi-claudecode.sh
```

The script will prompt you for:

| Prompt | Type | Description |
|---|---|---|
| **Workspace URL** | Text input | Your Databricks workspace URL (e.g. `https://my-workspace.cloud.databricks.com`) |
| **CLI profile name** | Text input | Name for the Databricks CLI authentication profile (e.g. `my-profile`) |
| **Model** | Text input | The model to use. Defaults to `databricks-claude-opus-4-6` |
| **Command name** | Arrow-key selector | The shell command to invoke Claude with FMAPI (see [Command name options](#command-name-options) below) |
| **Settings location** | Arrow-key selector | Where to write the `.claude/settings.json` file (current directory, home directory, or a custom path) |

> The **Command name** and **Settings location** prompts use an interactive arrow-key selector &mdash; use the up/down arrow keys to navigate and Enter to confirm.

Once complete, open a new terminal (or `source ~/.zshrc`) and run:

```bash
fmapi-claude   # default, or whatever command name you chose
```

### Command name options

During setup you can choose what command to use:

| Option | Description |
|---|---|
| `fmapi-claude` | **Default.** Adds a separate command alongside the original `claude` command. |
| `claude` | Overrides the default `claude` command so every invocation goes through FMAPI with automatic token refresh. The underlying `claude` binary is still called via the wrapper. |
| Custom name | Use any name you like (e.g. `dbx-claude`, `my-claude`). Must start with a letter or underscore and contain only letters, numbers, hyphens, and underscores. |

If you re-run the script and pick a different command name, the old wrapper is automatically removed.

## What the Script Does

### 1. Installs dependencies

- **Claude Code** &mdash; installed via `curl -fsSL https://claude.ai/install.sh | bash` if not already present.
- **Databricks CLI** &mdash; installed via Homebrew (`brew tap databricks/tap && brew install databricks`) if not already present.

### 2. Authenticates with Databricks

Attempts to retrieve an OAuth token using `databricks auth token --profile <profile>`. If no valid token exists, it triggers `databricks auth login` to start the OAuth flow in your browser, then retrieves the token.

### 3. Writes `.claude/settings.json`

Creates or merges environment variables into your Claude Code settings file at the chosen location. The settings configure Claude Code to route API calls through your Databricks workspace:

| Variable | Value |
|---|---|
| `ANTHROPIC_MODEL` | Selected model (default: `databricks-claude-opus-4-6`) |
| `ANTHROPIC_BASE_URL` | `<workspace-url>/serving-endpoints/anthropic` |
| `ANTHROPIC_AUTH_TOKEN` | Your Databricks OAuth token |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `databricks-claude-opus-4-6` |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `databricks-claude-sonnet-4-5` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `databricks-claude-haiku-4-5` |
| `ANTHROPIC_CUSTOM_HEADERS` | `x-databricks-use-coding-agent-mode: true` |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | `1` |

If the settings file already exists, the script merges the new `env` values into it without overwriting other settings.

### 4. Adds the `fmapi-claude` shell wrapper

Appends a shell function to your `~/.zshrc` (or `~/.bashrc`) that wraps the `claude` command with automatic token refresh logic.

## Using the wrapper command

The wrapper (default: `fmapi-claude`, or whatever name you chose during setup) is a drop-in replacement for the `claude` command. It accepts all the same arguments and flags &mdash; the only difference is that it checks your Databricks token before each invocation and refreshes it if it has expired.

```bash
# Start an interactive session
fmapi-claude

# Run a one-shot prompt
fmapi-claude -p "explain this codebase"

# Resume a conversation
fmapi-claude --continue

# Any other claude flags work as usual
fmapi-claude --help
```

> **Tip:** If you chose `claude` as the command name, just replace `fmapi-claude` with `claude` in the examples above &mdash; every `claude` invocation will automatically refresh tokens.

### How token refresh works

Each time you run the wrapper command:

1. Reads the current token from your `settings.json`.
2. Makes a lightweight API call to your workspace to check if the token is still valid.
3. If expired, attempts to get a new token from `databricks auth token --profile <profile>`.
4. If that also fails (e.g. the refresh token expired), opens the OAuth login flow via `databricks auth login`.
5. Writes the new token back into `settings.json` and launches Claude Code.

If you use the plain `claude` command instead, it will still work as long as the token in `settings.json` hasn't expired &mdash; but it won't auto-refresh.

## Available Models

| Model ID | Description |
|---|---|
| `databricks-claude-opus-4-6` | Claude Opus 4.6 (default) |
| `databricks-claude-sonnet-4-5` | Claude Sonnet 4.5 |
| `databricks-claude-haiku-4-5` | Claude Haiku 4.5 |

## Re-running the Script

You can safely re-run `setup-fmapi-claudecode.sh` at any time to:

- Update the workspace URL, profile, or model
- Refresh an expired token
- Repair a missing or corrupted settings file

The script will update the existing shell wrapper in-place rather than appending a duplicate.

## Troubleshooting

**"Workspace URL must start with https://"**
Provide the full URL including the scheme, e.g. `https://my-workspace.cloud.databricks.com`.

**Token refresh fails silently**
Ensure the Databricks CLI profile name matches what you used during setup. Check with `databricks auth env --profile <profile>`.

**`fmapi-claude: command not found`**
Run `source ~/.zshrc` (or `source ~/.bashrc`) or open a new terminal after running the setup script.

**Claude Code returns authentication errors**
Your OAuth token may have fully expired. Run `fmapi-claude` to trigger a refresh, or re-run the setup script.
