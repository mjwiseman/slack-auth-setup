# Slack MCP Auth Setup

This repository contains setup notes and helpers for connecting MCP clients to Slack using the official Slack MCP server.

## Recommended Setup

VS Code and GitHub Copilot CLI can now handle the Slack OAuth flow directly with a Slack app Client ID. This is the preferred setup because users do not need a shared Slack token, a locally generated `SLACK_MCP_TOKEN`, or the Slack app Client Secret.

Use these guides first:

- [Slack MCP App Admin Guide](./slack-app-admin-guide.md)
- [Slack MCP User Setup Guide](./user-setup-guide.md)

The PowerShell and Python scripts in this repository are kept as an older fallback for manually generating and storing a bearer token. They should not be needed for the OAuth Client ID setup.

The legacy script setup below uses a confidential-client OAuth flow. It requires the Slack app client secret and was used for testing the long-lived-token alternative. Treat the script, shell history, and generated environment files as sensitive.

The important bit: each person authorizes Slack as themselves. MCP clients then see the Slack messages, channels, and threads that the current Slack user can access, rather than using a shared team token.

## Why This Exists

The original setup pattern used one shared Slack user token in MCP client configuration. That works for basic testing, but it means every user is effectively searching Slack as the person who created that token. They may see private channels that person can access, and they may miss private channels that only they personally can access.

The goal of these helpers is to make the better pattern easy enough for day-to-day company use:

1. A Slack app admin creates and approves one internal Slack MCP app.
2. Each person authorizes that same app with their own Slack account.
3. VS Code or GitHub Copilot CLI stores and refreshes the OAuth credentials it needs.
4. Slack MCP then runs with that person's Slack permissions.

Earlier PKCE testing with our own helper scripts returned expiring Slack tokens, but the native VS Code and Copilot CLI OAuth flows handle token management themselves. The older confidential-client scripts are still in the repo as a fallback, but the simpler Client ID setup is now preferred.

## What This Sets Up

The setup scripts:

1. Open Slack in your browser and ask you to approve the Slack app.
2. Save your Slack user token as `SLACK_MCP_TOKEN`.
3. Optionally add Slack MCP to VS Code.
4. Optionally add Slack MCP to GitHub Copilot CLI.

The VS Code MCP entry looks like this:

```json
{
  "servers": {
    "slack": {
      "type": "http",
      "url": "https://mcp.slack.com/mcp",
      "headers": {
        "Authorization": "Bearer ${env:SLACK_MCP_TOKEN}"
      }
    }
  }
}
```

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

- Windows 10 or 11 with PowerShell, or macOS with Python 3.
- VS Code and/or GitHub Copilot CLI if you want the script to configure those clients.
- Access to the Slack workspace.
- The Slack app's Client ID.
- The Slack app's Client Secret.

The Slack app must already be configured by an app admin:

- Internal Slack app.
- Slack MCP enabled.
- PKCE not enabled. If PKCE has already been enabled for the app, Slack says that is a one-way setting unless Slack support changes it.
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

This setup intentionally does not use PKCE. It exchanges the OAuth code with the Slack client secret so Slack treats the localhost redirect as a confidential-client flow.

## Windows Setup

Open PowerShell in this folder and run:

```powershell
.\setup-slack-mcp-copilot.ps1 -ClientId "YOUR_SLACK_CLIENT_ID" -ClientSecret "YOUR_SLACK_CLIENT_SECRET"
```

Your browser will open Slack. Approve the requested permissions.

When prompted, choose whether to add Slack MCP to VS Code and/or GitHub Copilot CLI.

If selected, Windows config paths are:

```text
%APPDATA%\Code\User\mcp.json
%USERPROFILE%\.copilot\mcp-config.json
```

Open a new terminal before using shell-based tools so `SLACK_MCP_TOKEN` is available.

Fully restart VS Code before using the Slack MCP server there.

## macOS Setup

Run:

```bash
python3 setup-slack-mcp-token-mac.py \
  --client-id "YOUR_SLACK_CLIENT_ID" \
  --client-secret "YOUR_SLACK_CLIENT_SECRET"
```

Your browser will open Slack. Approve the requested permissions.

When prompted, choose whether to add Slack MCP to VS Code and/or GitHub Copilot CLI.

If selected, macOS config paths are:

```text
~/Library/Application Support/Code/User/mcp.json
~/.copilot/mcp-config.json
```

Open a new terminal before using shell-based tools so `SLACK_MCP_TOKEN` is available.

Fully restart VS Code before using the Slack MCP server there. The macOS script also writes a LaunchAgent so GUI apps can receive `SLACK_MCP_TOKEN` on future logins.

## Test

Check the token exists.

Windows:

```powershell
echo $env:SLACK_MCP_TOKEN
```

macOS:

```bash
echo "$SLACK_MCP_TOKEN"
```

Do not paste or share the token.

You can also check Slack accepts the token:

Windows:

```powershell
curl.exe -X POST "https://slack.com/api/auth.test" -H "Authorization: Bearer $env:SLACK_MCP_TOKEN"
```

macOS:

```bash
curl -X POST "https://slack.com/api/auth.test" \
  -H "Authorization: Bearer $SLACK_MCP_TOKEN"
```

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

The setup script also verifies the returned token with Slack `auth.test` and prints the Slack user and workspace IDs. Use that line as the source of truth for which Slack user the token belongs to.

## Troubleshooting

### PowerShell says scripts are disabled

Run the script with a process-local execution policy:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-slack-mcp-copilot.ps1 -ClientId "YOUR_SLACK_CLIENT_ID" -ClientSecret "YOUR_SLACK_CLIENT_SECRET"
```

### Port 53682 is already in use

Ask a Slack app admin to add another redirect URL, for example:

```text
http://localhost:53683/slack/oauth/callback
```

Then rerun:

```powershell
.\setup-slack-mcp-copilot.ps1 -ClientId "YOUR_SLACK_CLIENT_ID" -ClientSecret "YOUR_SLACK_CLIENT_SECRET" -RedirectPort 53683
```

### Slack returns `bad_redirect_uri`

The redirect URL in the Slack app does not exactly match the URL used by the script. Add this exact URL to the Slack app:

```text
http://localhost:53682/slack/oauth/callback
```

If you used `-RedirectPort`, add the matching port instead.

### Slack returns `bad_client_secret`

The client secret is missing, wrong, or belongs to a different Slack app than the client ID.

### Slack returns `invalid_arguments`

If the Slack app has PKCE enabled, Slack may reject a confidential-client exchange for a localhost redirect. Use an app that has not opted into PKCE for this alternative flow.

### Slack returns `access_denied`

You cancelled or denied the Slack approval request. Rerun the script and approve the requested permissions.

### `/mcp show slack` does not work

Check that your Copilot CLI config contains a `slack` entry.

Windows:

```text
%USERPROFILE%\.copilot\mcp-config.json
```

macOS:

```text
~/.copilot/mcp-config.json
```

Check that the token is available in the terminal where you started Copilot CLI:

Windows:

```powershell
echo $env:SLACK_MCP_TOKEN
```

macOS:

```bash
echo "$SLACK_MCP_TOKEN"
```

If it is blank, open a new terminal window and try again.

### VS Code cannot read `SLACK_MCP_TOKEN`

Fully quit and reopen VS Code after running the setup script.

On macOS, check the GUI launch environment:

```bash
launchctl getenv SLACK_MCP_TOKEN
```

If your shell has an older token in `~/.zshrc`, `~/.zprofile`, or `~/.zshenv`, remove the stale entry and rerun the setup script.

### Existing MCP config parse error

The scripts create a backup before changing an existing MCP config. If setup fails while updating the config, the backup file will be next to the file that could not be parsed.

If the parse error mentions a missing `Depth` parameter on Windows, download the latest version of this repository and rerun the script. Older versions of the helper used a PowerShell 7 parameter that is not available in Windows PowerShell 5.1.

### Copilot cannot access a private channel

This setup uses your own Slack permissions. Copilot can only access private channels and DMs that your Slack account can access.

### Copilot appears to use the wrong Slack user

First check the user printed by the setup script:

```text
Slack token verified for user '...' (...) in workspace '...' (...).
```

If that line shows the wrong Slack user, the browser authorized the app as the wrong logged-in Slack account. Sign out of Slack in the browser, use a private browser window, or switch Slack accounts before rerunning the setup script.

If that line shows the correct Slack user but Copilot still behaves like an old user, restart Copilot CLI or run:

```text
/mcp reload slack
```

If it still looks stale, run the setup with a temporary server name to avoid any cached MCP auth/session state:

```powershell
.\setup-slack-mcp-copilot.ps1 -ClientId "YOUR_SLACK_CLIENT_ID" -ClientSecret "YOUR_SLACK_CLIENT_SECRET" -ServerName "slack-test"
```

Then start a new Copilot CLI session and check:

```text
/mcp show slack-test
```

## Security Notes

- This setup requires the Slack client secret.
- The Slack token is stored as `SLACK_MCP_TOKEN`.
- VS Code and Copilot CLI configs reference `SLACK_MCP_TOKEN` rather than storing the bearer token directly. VS Code uses `${env:SLACK_MCP_TOKEN}`; Copilot CLI uses `${SLACK_MCP_TOKEN}`.
- The token is not printed by the script.
- On macOS, the token is stored in `~/.zshenv` and a LaunchAgent plist so shell and GUI apps can read it.
- On Windows, the token is stored as a user environment variable.
- Do not share the client secret or token, or paste them into chat, issues, logs, or screenshots.

## References

- [Slack MCP server docs](https://docs.slack.dev/ai/slack-mcp-server/)
- [Slack PKCE docs](https://docs.slack.dev/authentication/using-pkce/)
- [Slack oauth.v2.user.access](https://docs.slack.dev/reference/methods/oauth.v2.user.access)
- [GitHub Copilot CLI MCP docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers)
