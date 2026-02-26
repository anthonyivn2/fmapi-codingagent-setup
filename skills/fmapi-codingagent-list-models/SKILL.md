---
name: fmapi-codingagent-list-models
description: List all serving endpoints available in your Databricks workspace
user_invocable: true
---

# FMAPI List Models

List all serving endpoints available in your Databricks workspace to discover model names for FMAPI configuration.

## Instructions

1. Determine the install path of this plugin. This SKILL.md file is located at `<install-path>/skills/fmapi-codingagent-list-models/SKILL.md`, so the setup script is two directories up at `<install-path>/setup-fmapi-claudecode.sh`.

2. Run the list-models command:

```bash
bash "<install-path>/setup-fmapi-claudecode.sh" --list-models
```

3. Present the output to the user. The command displays a table of all serving endpoints with:

   - **ENDPOINT NAME** — The name of the serving endpoint
   - **STATE** — Whether the endpoint is READY or NOT_READY
   - **TYPE** — The endpoint type

4. The table uses visual markers:
   - **`>` (green)** — Currently configured model (in your settings)
   - **`*` (cyan)** — Claude/Anthropic endpoint (relevant for FMAPI)

5. If the command fails:
   - **No config found**: suggest `/fmapi-codingagent-setup` first
   - **OAuth expired**: suggest `/fmapi-codingagent-reauth`
   - **No endpoints found**: the workspace may not have FMAPI enabled
