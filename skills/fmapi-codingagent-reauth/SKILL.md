---
name: fmapi-codingagent-reauth
description: Re-authenticate Databricks OAuth session for FMAPI
user_invocable: true
---

# FMAPI Re-authentication

Re-authenticate your Databricks OAuth session without re-running the full setup.

## Instructions

1. Determine the install path of this plugin. This SKILL.md file is located at `<install-path>/skills/fmapi-codingagent-reauth/SKILL.md`, so the setup script is two directories up at `<install-path>/setup-fmapi-claudecode.sh`.

2. Run the reauth command:

```bash
bash "<install-path>/setup-fmapi-claudecode.sh" --reauth
```

3. This command will:
   - Discover the existing FMAPI configuration
   - Trigger `databricks auth login` to start an OAuth flow in the browser
   - Verify the new session is valid
   - Print a success or failure message

4. If no existing FMAPI configuration is found, inform the user they need to run `/fmapi-codingagent-setup` first.
