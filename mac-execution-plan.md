# Mac Slack MCP Token Setup Plan

## Summary

Create a macOS helper that performs the same Slack OAuth user-token flow as the confidential-client Windows branch, but only stores the resulting Slack token as a user environment variable. It must not create or update Copilot MCP config files. Users can then reference the environment variable wherever their MCP client needs it.

Deliverable:

- `setup-slack-mcp-token-mac.py`

## Intended User Flow

The user runs:

```bash
python3 setup-slack-mcp-token-mac.py \
  --client-id "YOUR_SLACK_CLIENT_ID" \
  --client-secret "YOUR_SLACK_CLIENT_SECRET"
```

The script:

1. Starts a temporary local callback listener.
2. Opens Slack OAuth in the browser.
3. Receives the Slack callback on localhost.
4. Exchanges the OAuth code for a Slack user token using the provided client secret.
5. Verifies the returned token with Slack `auth.test`.
6. Saves the token as `SLACK_MCP_TOKEN` for the macOS user.
7. Prints the Slack user/workspace identity, but never prints the token.

## Slack App Requirements

The Slack app must be configured before the script is used:

- Slack MCP enabled.
- Required scopes added under **User Token Scopes**.
- Token rotation disabled if the goal is a long-lived token.
- PKCE not enabled for this confidential-client flow.
- Redirect URL added exactly as:

```text
http://localhost:53682/slack/oauth/callback
```

Required user token scopes:

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

## Implementation Details

Use Python 3 rather than Bash so the OAuth callback, URL handling, JSON parsing, and Slack API calls are reliable without extra dependencies.

Hardcode:

- Redirect port: `53682`
- Redirect path: `/slack/oauth/callback`
- Redirect URI: `http://localhost:53682/slack/oauth/callback`
- Environment variable name: `SLACK_MCP_TOKEN`
- Slack OAuth authorize endpoint: `https://slack.com/oauth/v2_user/authorize`
- Slack token endpoint: `https://slack.com/api/oauth.v2.user.access`
- Slack verification endpoint: `https://slack.com/api/auth.test`
- User token scopes listed above

Supported arguments:

- `--client-id`: Slack app client ID.
- `--client-secret`: Slack app client secret.

Do not add options for redirect port, server name, scopes, or Copilot config paths. The script is intentionally narrow: it gets a token and stores it for the user.

## Token Exchange Flow

The script should:

- Generate a cryptographically random OAuth `state`.
- Build the authorize URL with `client_id`, hardcoded scopes, hardcoded `redirect_uri`, and `state`.
- Open the authorize URL with `webbrowser.open()`.
- Start a localhost HTTP server and wait for one request to `/slack/oauth/callback`.
- Validate the returned `state`.
- Handle Slack callback errors such as `access_denied`.
- Exchange the returned `code` by posting form data to `oauth.v2.user.access`:

```text
client_id=...
client_secret=...
code=...
redirect_uri=http://localhost:53682/slack/oauth/callback
grant_type=authorization_code
```

- Fail clearly on Slack errors, especially:
  - `bad_redirect_uri`
  - `bad_client_secret`
  - `invalid_code`
  - `invalid_arguments`
- Fail if Slack does not return `access_token`.

## Token Verification

After receiving the token, call Slack `auth.test` using:

```text
Authorization: Bearer <access_token>
```

If verification succeeds, print:

- Slack user name
- Slack user ID
- Slack workspace name
- Slack workspace ID
- `expires_in` if Slack returns it

If `auth.test` fails, do not save the token.

## macOS Environment Storage

Store the token in both places:

1. Current user launch environment:

```bash
launchctl setenv SLACK_MCP_TOKEN "<token>"
```

2. Persistent shell startup file:

```text
~/.zshenv
```

The script should add or replace exactly one managed line:

```bash
export SLACK_MCP_TOKEN="<token>"
```

Use a timestamped backup before modifying an existing `~/.zshenv`.

After saving, print:

```text
SLACK_MCP_TOKEN has been saved for this macOS user.
Open a new terminal before using it from shell-based tools.
```

Do not print the token.

## Validation Steps

User can validate with:

```bash
launchctl getenv SLACK_MCP_TOKEN
```

and in a new terminal:

```bash
echo "$SLACK_MCP_TOKEN"
```

The user can test Slack auth with:

```bash
curl -X POST "https://slack.com/api/auth.test" \
  -H "Authorization: Bearer $SLACK_MCP_TOKEN"
```

Expected result includes:

```json
{
  "ok": true,
  "team": "...",
  "user": "..."
}
```

If `expires_in` appears, the token is expiring and the user may need to rerun the setup after expiry.

## Security Notes

- The client secret is passed as an argument, not stored in the script.
- The token is saved to the user's environment and `~/.zshenv`; both should be treated as sensitive.
- The script must not log the client secret, OAuth code, access token, or refresh token.
- Shell history may capture the client secret if passed directly on the command line. A later improvement could prompt for the secret interactively instead.

## Out of Scope

- Creating or editing `~/.copilot/mcp-config.json`.
- Supporting multiple MCP server names.
- Custom scope selection.
- Custom redirect ports.
- PKCE flow.
- Refresh-token support.
