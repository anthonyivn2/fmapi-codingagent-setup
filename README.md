# Claude Code using Databricks Foundational Model API

Set up [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to run against the Anthropic models served through [Databricks Foundation Model API (FMAPI)](https://docs.databricks.com/en/machine-learning/foundation-models/index.html) in a single command.

## Prerequisites

- **macOS** with `zsh` or `bash`
- [Homebrew](https://brew.sh/) (`brew`)
- [`jq`](https://jqlang.github.io/jq/) (install with `brew install jq`)
- A Databricks workspace with FMAPI enabled

## Quick Start

```bash
bash setup-fmapi-claudecode.sh
```

The script will prompt you for:

| Prompt | Description |
|---|---|
| **Workspace URL** | Your Databricks workspace URL (e.g. `https://my-workspace.cloud.databricks.com`) |
| **CLI profile name** | Name for the Databricks CLI authentication profile (e.g. `my-profile`) |
| **Model** | The model to use. Defaults to `databricks-claude-opus-4-6` |
| **Settings location** | Where to write the `.claude/settings.json` file (current directory, home directory, or a custom path) |

Once complete, open a new terminal (or `source ~/.zshrc`) and run:

```bash
dbx-fmapi-claude
```

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

### 4. Adds the `dbx-fmapi-claude` shell wrapper

Appends a shell function to your `~/.zshrc` (or `~/.bashrc`) that wraps the `claude` command with automatic token refresh logic.

## Using `dbx-fmapi-claude`

`dbx-fmapi-claude` is a drop-in replacement for the `claude` command. It accepts all the same arguments and flags &mdash; the only difference is that it checks your Databricks token before each invocation and refreshes it if it has expired.

```bash
# Start an interactive session
dbx-fmapi-claude

# Run a one-shot prompt
dbx-fmapi-claude -p "explain this codebase"

# Resume a conversation
dbx-fmapi-claude --continue

# Any other claude flags work as usual
dbx-fmapi-claude --help
```

### How token refresh works

Each time you run `dbx-fmapi-claude`:

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

**`dbx-fmapi-claude: command not found`**
Run `source ~/.zshrc` (or `source ~/.bashrc`) or open a new terminal after running the setup script.

**Claude Code returns authentication errors**
Your OAuth token may have fully expired. Run `dbx-fmapi-claude` to trigger a refresh, or re-run the setup script.
