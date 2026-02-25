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
| **Model** | Text input | The model to use. Defaults to `databricks-claude-opus-4-6` |
| **Command name** | Arrow-key selector | The shell command to invoke Claude Code with FMAPI (see [Command name options](#command-name-options) below) |
| **Settings location** | Arrow-key selector | Where to write the `.claude/settings.json` file (current directory, home directory, or a custom path) |
| **PAT lifetime** | Arrow-key selector | How long the Personal Access Token should last (1 day, 3 days, 5 days, or 7 days) |

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

### What the Script Does

#### 1. Installs dependencies

- **Claude Code** &mdash; installed via `curl -fsSL https://claude.ai/install.sh | bash` if not already present.
- **Databricks CLI** &mdash; installed via Homebrew (`brew tap databricks/tap && brew install databricks`) if not already present.

#### 2. Authenticates with Databricks

Establishes an OAuth session using `databricks auth token --profile <profile>`. If no valid session exists, it triggers `databricks auth login` to start the OAuth flow in your browser. Once authenticated, the script revokes any old FMAPI PATs and creates a new Personal Access Token (PAT) with the chosen lifetime. The PAT is used as the `ANTHROPIC_AUTH_TOKEN` for Claude Code.

#### 3. Writes `.claude/settings.json`

Creates or merges environment variables into your Claude Code settings file at the chosen location. The settings configure Claude Code to route API calls through your Databricks workspace:

| Variable | Value |
|---|---|
| `ANTHROPIC_MODEL` | Selected model (default: `databricks-claude-opus-4-6`) |
| `ANTHROPIC_BASE_URL` | `<workspace-url>/serving-endpoints/anthropic` |
| `ANTHROPIC_AUTH_TOKEN` | Your Databricks Personal Access Token (PAT) |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `databricks-claude-opus-4-6` |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `databricks-claude-sonnet-4-5` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `databricks-claude-haiku-4-5` |
| `ANTHROPIC_CUSTOM_HEADERS` | `x-databricks-use-coding-agent-mode: true` |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | `1` |

If the settings file already exists, the script merges the new `env` values into it without overwriting other settings.

#### 4. Adds the `fmapi-claude` shell wrapper

Appends a shell function to your `~/.zshrc` (or `~/.bashrc`) that wraps the `claude` command with automatic token refresh logic.

### Using the wrapper command

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

#### How token refresh works

Each time you run the wrapper command:

1. Reads the PAT expiry time stored in `settings.json` (no network call needed).
2. If the PAT hasn't expired, launches Claude Code immediately.
3. If expired, ensures the OAuth session is still valid (triggers `databricks auth login` if needed).
4. Revokes any old FMAPI PATs from the workspace.
5. Creates a new PAT with the configured lifetime and writes it back into `settings.json`.

If you use the plain `claude` command instead, it will still work as long as the PAT in `settings.json` hasn't expired &mdash; but it won't auto-refresh.

### Available Models

Models available through FMAPI depend on what is enabled in your Databricks workspace. The setup script supports:

| Model ID | Description |
|---|---|
| `databricks-claude-opus-4-6` | Claude Opus 4.6 (default) |
| `databricks-claude-sonnet-4-5` | Claude Sonnet 4.5 |
| `databricks-claude-haiku-4-5` | Claude Haiku 4.5 |

### Uninstalling

To remove all FMAPI artifacts created by the setup script:

```bash
bash setup-fmapi-claudecode.sh --uninstall
```

The uninstall process:

1. **Discovers wrappers** — Scans both `~/.zshrc` and `~/.bashrc` for any FMAPI wrapper blocks, regardless of the command name used during setup.
2. **Cleans settings files** — Removes FMAPI-specific keys (`ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, etc.) and the `_fmapi_meta` block from `.claude/settings.json`. If no other settings remain, the file is deleted. Non-FMAPI settings are preserved.
3. **Optionally revokes PATs** — With a separate confirmation prompt, revokes any Databricks PATs whose comment starts with "Claude Code FMAPI". If you decline, the tokens will expire on their own.

Re-running `--uninstall` when nothing is installed is safe and will print "Nothing to uninstall."

### Re-running the Script

You can safely re-run `setup-fmapi-claudecode.sh` at any time to:

- Update the workspace URL, profile, or model
- Refresh an expired token
- Repair a missing or corrupted settings file

The script will update the existing shell wrapper in-place rather than appending a duplicate.

### Troubleshooting

**"Workspace URL must start with https://"**
Provide the full URL including the scheme, e.g. `https://my-workspace.cloud.databricks.com`.

**Token refresh fails silently**
Ensure the Databricks CLI profile name matches what you used during setup. Check with `databricks auth env --profile <profile>`.

**`fmapi-claude: command not found`**
Run `source ~/.zshrc` (or `source ~/.bashrc`) or open a new terminal after running the setup script.

**Claude Code returns authentication errors**
Your PAT may have expired. Run `fmapi-claude` to trigger automatic PAT refresh, or re-run the setup script.

## OpenAI Codex

FMAPI supports OpenAI Codex today. A setup script for this repo is not yet available &mdash; contributions welcome.

## Gemini CLI

FMAPI supports Gemini CLI today. A setup script for this repo is not yet available &mdash; contributions welcome.
