---
name: fmapi-codingagent-status
description: Check FMAPI configuration health — workspace, PAT status, OAuth session, and model settings
user_invocable: true
---

# FMAPI Status Check

Check the health of your Databricks Foundation Model API (FMAPI) configuration for Claude Code.

## Instructions

1. Determine the install path of this plugin. This SKILL.md file is located at `<install-path>/skills/fmapi-codingagent-status/SKILL.md`, so the setup script is two directories up at `<install-path>/setup-fmapi-claudecode.sh`.

2. Run the status command:

```bash
bash "<install-path>/setup-fmapi-claudecode.sh" --status
```

3. Present the output to the user. The status dashboard shows:

   - **Green (healthy)**: PAT has more than 2 hours remaining, OAuth session is active. No action needed.
   - **Yellow (warning)**: PAT has less than 2 hours remaining. Suggest running `/fmapi-codingagent-refresh` to rotate the token.
   - **Red (expired/missing)**: PAT is expired or no configuration found. Suggest running `/fmapi-codingagent-setup` to reconfigure, or `/fmapi-codingagent-refresh` if only the PAT expired.

4. If the command exits with an error indicating no config was found, inform the user they need to run `/fmapi-codingagent-setup` first.
