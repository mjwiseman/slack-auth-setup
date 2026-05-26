#!/usr/bin/env python3
"""
Authorize a Slack MCP app on macOS and save the returned user token as SLACK_MCP_TOKEN.

This helper uses Slack's confidential-client OAuth exchange. It requires the Slack client ID and
client secret as command-line arguments. It does not create or edit MCP client configuration files.
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import http.server
import json
import os
import secrets
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path
from typing import Any


REDIRECT_PORT = 53682
REDIRECT_PATH = "/slack/oauth/callback"
REDIRECT_URI = f"http://localhost:{REDIRECT_PORT}{REDIRECT_PATH}"
ENV_VAR_NAME = "SLACK_MCP_TOKEN"
AUTHORIZE_URL = "https://slack.com/oauth/v2_user/authorize"
TOKEN_URL = "https://slack.com/api/oauth.v2.user.access"
AUTH_TEST_URL = "https://slack.com/api/auth.test"
DEFAULT_SCOPES = [
    "search:read.public",
    "search:read.private",
    "search:read.mpim",
    "search:read.im",
    "channels:history",
    "groups:history",
    "mpim:history",
    "im:history",
]


class SetupError(Exception):
    """A setup failure with a user-facing message."""


class CallbackServer(http.server.HTTPServer):
    timeout = 300

    def __init__(self, server_address: tuple[str, int], handler_class: type[http.server.BaseHTTPRequestHandler]):
        super().__init__(server_address, handler_class)
        self.callback_query: dict[str, list[str]] | None = None
        self.callback_path: str | None = None


class OAuthCallbackHandler(http.server.BaseHTTPRequestHandler):
    server: CallbackServer

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        self.server.callback_path = parsed.path
        self.server.callback_query = urllib.parse.parse_qs(parsed.query)

        if parsed.path != REDIRECT_PATH:
            self._write_html(
                404,
                "Unexpected callback path",
                f"Expected <code>{html.escape(REDIRECT_PATH)}</code> but received <code>{html.escape(parsed.path)}</code>.",
            )
            return

        self._write_html(
            200,
            "Slack authorization complete",
            "Slack authorization succeeded. Return to your terminal to finish setup.",
        )

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _write_html(self, status: int, title: str, message: str) -> None:
        body = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{html.escape(title)}</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 48px; line-height: 1.5; color: #1f2328; }}
    main {{ max-width: 680px; }}
    code {{ background: #f6f8fa; padding: 2px 5px; border-radius: 4px; }}
  </style>
</head>
<body>
  <main>
    <h1>{html.escape(title)}</h1>
    <p>{message}</p>
    <p>You can close this browser tab.</p>
  </main>
</body>
</html>
"""
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Authorize Slack MCP and save the returned user token as SLACK_MCP_TOKEN on macOS."
    )
    parser.add_argument("--client-id", required=True, help="Slack app client ID.")
    parser.add_argument("--client-secret", required=True, help="Slack app client secret.")
    return parser.parse_args()


def build_authorize_url(client_id: str, state: str) -> str:
    query = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "scope": ",".join(DEFAULT_SCOPES),
            "redirect_uri": REDIRECT_URI,
            "state": state,
        }
    )
    return f"{AUTHORIZE_URL}?{query}"


def wait_for_callback() -> dict[str, list[str]]:
    try:
        server = CallbackServer(("localhost", REDIRECT_PORT), OAuthCallbackHandler)
    except OSError as exc:
        raise SetupError(
            f"Could not start the local callback listener on {REDIRECT_URI}. "
            "Check whether port 53682 is already in use."
        ) from exc

    with server:
        server.handle_request()

    if server.callback_query is None:
        raise SetupError("Timed out waiting for the Slack OAuth callback. Rerun setup when ready.")

    if server.callback_path != REDIRECT_PATH:
        raise SetupError(f"Received an unexpected callback path: {server.callback_path}")

    return server.callback_query


def first_query_value(query: dict[str, list[str]], name: str) -> str | None:
    values = query.get(name)
    if not values:
        return None
    return values[0]


def post_form(url: str, data: dict[str, str], headers: dict[str, str] | None = None) -> dict[str, Any]:
    encoded = urllib.parse.urlencode(data).encode("utf-8")
    request_headers = {"Content-Type": "application/x-www-form-urlencoded"}
    if headers:
        request_headers.update(headers)

    request = urllib.request.Request(url, data=encoded, headers=request_headers, method="POST")
    return read_json_response(request)


def post_without_body(url: str, headers: dict[str, str]) -> dict[str, Any]:
    request = urllib.request.Request(url, data=b"", headers=headers, method="POST")
    return read_json_response(request)


def read_json_response(request: urllib.request.Request) -> dict[str, Any]:
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        raise SetupError(f"HTTP request failed with status {exc.code}: {raw}") from exc
    except urllib.error.URLError as exc:
        raise SetupError(f"HTTP request failed: {exc.reason}") from exc

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SetupError("Slack returned a response that was not valid JSON.") from exc

    if not isinstance(parsed, dict):
        raise SetupError("Slack returned an unexpected JSON response.")

    return parsed


def exchange_code_for_token(client_id: str, client_secret: str, code: str) -> dict[str, Any]:
    token_response = post_form(
        TOKEN_URL,
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "code": code,
            "redirect_uri": REDIRECT_URI,
            "grant_type": "authorization_code",
        },
    )

    if token_response.get("ok") is not True:
        error = str(token_response.get("error") or "unknown_error")
        if error == "bad_redirect_uri":
            raise SetupError(f"Slack returned bad_redirect_uri. Add this exact redirect URL to the Slack app: {REDIRECT_URI}")
        if error == "bad_client_secret":
            raise SetupError("Slack returned bad_client_secret. Confirm the client secret matches the Slack app client ID.")
        if error == "invalid_code":
            raise SetupError("Slack returned invalid_code. Rerun setup and complete the browser approval promptly.")
        if error == "invalid_arguments":
            raise SetupError(
                "Slack returned invalid_arguments. If this Slack app has PKCE enabled, use an app that has not opted into PKCE for this confidential-client flow."
            )
        raise SetupError(f"Slack token exchange failed: {error}")

    if not token_response.get("access_token"):
        raise SetupError("Slack token exchange succeeded but did not return access_token.")

    return token_response


def verify_token(access_token: str) -> dict[str, Any]:
    auth_response = post_without_body(AUTH_TEST_URL, {"Authorization": f"Bearer {access_token}"})
    if auth_response.get("ok") is not True:
        error = str(auth_response.get("error") or "unknown_error")
        raise SetupError(f"Slack auth.test failed: {error}")
    return auth_response


def shell_quote_double(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
    return f'"{escaped}"'


def save_launchctl_env(access_token: str) -> None:
    try:
        subprocess.run(["launchctl", "setenv", ENV_VAR_NAME, access_token], check=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise SetupError(f"Could not set {ENV_VAR_NAME} with launchctl.") from exc


def save_zshenv(access_token: str) -> Path:
    zshenv_path = Path.home() / ".zshenv"
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")

    if zshenv_path.exists():
        backup_path = zshenv_path.with_name(f"{zshenv_path.name}.bak-{timestamp}")
        shutil.copy2(zshenv_path, backup_path)
        existing_lines = zshenv_path.read_text(encoding="utf-8").splitlines()
    else:
        existing_lines = []

    managed_prefix = f"export {ENV_VAR_NAME}="
    new_line = f"export {ENV_VAR_NAME}={shell_quote_double(access_token)}"
    kept_lines = [line for line in existing_lines if not line.startswith(managed_prefix)]
    kept_lines.append(new_line)
    zshenv_path.write_text("\n".join(kept_lines) + "\n", encoding="utf-8")
    return zshenv_path


def main() -> int:
    args = parse_args()
    state = secrets.token_urlsafe(32)
    authorize_url = build_authorize_url(args.client_id, state)

    print(f"Opening Slack authorization in your browser...")
    print(f"Waiting for Slack to redirect back to {REDIRECT_URI}")
    webbrowser.open(authorize_url)

    query = wait_for_callback()
    error = first_query_value(query, "error")
    if error:
        raise SetupError(f"Slack authorization failed: {error}")

    returned_state = first_query_value(query, "state")
    if returned_state != state:
        raise SetupError("OAuth state mismatch. Rerun setup.")

    code = first_query_value(query, "code")
    if not code:
        raise SetupError("Slack did not return an authorization code.")

    print("Exchanging authorization code for a Slack user token...")
    token_response = exchange_code_for_token(args.client_id, args.client_secret, code)
    access_token = str(token_response["access_token"])

    print("Verifying Slack token...")
    auth_response = verify_token(access_token)
    print(
        "Slack token verified for user "
        f"'{auth_response.get('user')}' ({auth_response.get('user_id')}) "
        f"in workspace '{auth_response.get('team')}' ({auth_response.get('team_id')})."
    )
    if auth_response.get("expires_in") is not None:
        print(f"Slack reports this access token expires in {auth_response['expires_in']} seconds.")

    save_launchctl_env(access_token)
    zshenv_path = save_zshenv(access_token)

    print("")
    print(f"{ENV_VAR_NAME} has been saved for this macOS user.")
    print(f"Updated shell startup file: {zshenv_path}")
    print("Open a new terminal before using it from shell-based tools.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nSetup cancelled.", file=sys.stderr)
        raise SystemExit(130)
    except SetupError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
