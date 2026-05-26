# Slack MCP for GitHub Copilot CLI

This folder contains a Windows setup helper for connecting GitHub Copilot CLI to Slack using the official Slack MCP server.

The important bit: each person authorizes Slack as themselves. Copilot then sees the Slack messages, channels, and threads that the current Slack user can access, rather than using a shared team token.

## What This Sets Up

The setup script does three things:

1. Opens Slack in your browser and asks you to approve the internal Slack MCP app.
2. Stores your Slack user token in your Windows user environment as `SLACK_MCP_TOKEN`.
3. Adds the Slack MCP server to GitHub Copilot CLI at `%USERPROFILE%\.copilot\mcp-config.json`.

The Copilot CLI MCP entry looks like this:

```json
{
  "mcpServers": {
    "slack": {
      "type": "http",
      "url": "https://mcp.slack.com/mcp",
      "headers": {
        "Authorization": "Bearer ${SLACK_MCP_TOKEN}"
      },
      "tools": ["*"]
    }
  }
}
```

## Prerequisites

You need:

- Windows 10 or 11.
- PowerShell.
- GitHub Copilot CLI, usually launched with `gh copilot`.
- Access to the Slack workspace.
- The Slack app's Client ID.

The Slack app must already be configured by an app admin:

- Internal Slack app.
- Slack MCP enabled.
- PKCE enabled under **OAuth & Permissions**.
- Token rotation disabled for v1.
- Redirect URL added exactly as:

```text
http://localhost:53682/slack/oauth/callback
```

- These scopes added under **User Token Scopes**:

```text
search:read.public
search:read.private
search:read.mpim
search:read.im
channels:history
groups:history
mpim:history
im:history
```

Slack's PKCE setting is what lets this script exchange the OAuth code without using the app's client secret. If PKCE is not enabled, Slack will return `bad_client_secret` during setup.

## Setup

Open PowerShell in this folder and run:

```powershell
.\setup-slack-mcp-copilot.ps1 -ClientId "YOUR_SLACK_CLIENT_ID"
```

Your browser will open Slack. Approve the requested permissions.

When the script finishes, open a new PowerShell window so the new user environment variable is loaded.

## Test

Check the token exists:

```powershell
echo $env:SLACK_MCP_TOKEN
```

Do not paste or share the token.

If the token starts with `xoxe.xoxp-`, Slack has issued an expiring user token. That can still work for testing, but it may need reauthorization later unless refresh support is added.

Start Copilot CLI:

```powershell
gh copilot
```

Inside Copilot CLI, check the MCP server:

```text
/mcp show slack
```

Then try a Slack query:

```text
Use Slack MCP to search for recent messages mentioning actuals sync and summarise the results.
```

Copilot may ask for permission before using Slack MCP tools. Approve the Slack MCP tool call when prompted.

## Troubleshooting

### PowerShell says scripts are disabled

Run the script with a process-local execution policy:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-slack-mcp-copilot.ps1 -ClientId "YOUR_SLACK_CLIENT_ID"
```

### Port 53682 is already in use

Ask a Slack app admin to add another redirect URL, for example:

```text
http://localhost:53683/slack/oauth/callback
```

Then rerun:

```powershell
.\setup-slack-mcp-copilot.ps1 -ClientId "YOUR_SLACK_CLIENT_ID" -RedirectPort 53683
```

### Slack returns `bad_redirect_uri`

The redirect URL in the Slack app does not exactly match the URL used by the script. Add this exact URL to the Slack app:

```text
http://localhost:53682/slack/oauth/callback
```

If you used `-RedirectPort`, add the matching port instead.

### Slack returns `bad_client_secret`

The Slack app has not been opted into PKCE, or Slack is still treating the OAuth flow as a confidential-client flow.

Ask a Slack app admin to open the app settings and enable PKCE:

```text
OAuth & Permissions -> Proof Key for Code Exchange (PKCE) -> Opt In
```

Slack treats enabling PKCE as a one-way setting. That is expected for this helper because it is designed as a desktop/public-client flow and does not distribute the Slack client secret.

### Slack returns `access_denied`

You cancelled or denied the Slack approval request. Rerun the script and approve the requested permissions.

### `/mcp show slack` does not work

Check that `%USERPROFILE%\.copilot\mcp-config.json` contains a `slack` entry.

Check that the token is available in the terminal where you started Copilot CLI:

```powershell
echo $env:SLACK_MCP_TOKEN
```

If it is blank, open a new PowerShell window and try again.

### Existing `mcp-config.json` parse error

The script creates a backup before changing an existing Copilot MCP config. If setup fails while updating the config, the backup file will be next to:

```text
%USERPROFILE%\.copilot\mcp-config.json
```

If the parse error mentions a missing `Depth` parameter, download the latest version of this repository and rerun the script. Older versions of the helper used a PowerShell 7 parameter that is not available in Windows PowerShell 5.1.

### Copilot cannot access a private channel

This setup uses your own Slack permissions. Copilot can only access private channels and DMs that your Slack account can access.

## Security Notes

- The script uses PKCE and does not need the Slack client secret.
- The Slack token is stored in your Windows user environment as `SLACK_MCP_TOKEN`.
- The token is not printed by the script.
- Do not share the token or paste it into chat, issues, logs, or screenshots.

## References

- [Slack MCP server docs](https://docs.slack.dev/ai/slack-mcp-server/)
- [Slack PKCE docs](https://docs.slack.dev/authentication/using-pkce/)
- [Slack oauth.v2.user.access](https://docs.slack.dev/reference/methods/oauth.v2.user.access)
- [GitHub Copilot CLI MCP docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers)
