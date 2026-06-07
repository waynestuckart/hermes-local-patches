"""Credential handoff plugin — gives Hermes a safe way to ask for secrets.

The problem
-----------
Hermes (sensibly) won't accept API keys pasted into chat — conversation
turns are sent to the model provider and persisted to transcripts/logs, so
a key typed there is effectively burned. Its only fallback is "go edit
~/.hermes/.env in a terminal", which assumes the user is sitting at a
machine with one — not true when driving Hermes from a phone, Telegram,
etc.

The fix
-------
Mission Control (the web dashboard) already has exactly the mechanism this
needs: the Keys & Environment page PUTs straight from the browser to
``/api/env``, which writes the value to ``.env`` entirely server-side. The
plaintext never enters the agent loop, never becomes part of a prompt, and
never appears in a transcript — the dashboard process and the agent process
are the same binary, but the credential travels browser → HTTP handler →
disk, with no LLM call anywhere on that path.

This plugin just teaches Hermes to *use* that path instead of asking for
keys directly:

  1. Hermes calls ``request_credential(env_var, reason)``.
  2. The tool reports whether the var is already set — a bare ``true``/
     ``false``, never the value — plus instructions for Hermes to relay.
  3. The user opens Mission Control → Keys & Environment and pastes the
     key there themselves.
  4. Hermes calls ``request_credential`` again to confirm ``is_set`` is now
     true, and carries on — having never seen the plaintext at any point.

Guardrail
---------
Only environment variables Hermes already knows about — the union of
``REQUIRED_ENV_VARS`` and ``OPTIONAL_ENV_VARS`` from ``hermes_cli.config``,
the very same allowlist the dashboard's own Keys page is generated from —
can be requested. Anything else is refused. This keeps a confused or
adversarial model turn from steering a user toward pasting something
sensitive (``LD_PRELOAD``, a sudo password, ``PATH``, …) into a field that
was never meant to hold it.
"""

from __future__ import annotations

import json
import logging

logger = logging.getLogger(__name__)

REQUEST_CREDENTIAL_SCHEMA = {
    "type": "object",
    "properties": {
        "env_var": {
            "type": "string",
            "description": (
                "Exact environment-variable name the credential belongs in "
                "(e.g. OPENAI_API_KEY, TELEGRAM_BOT_TOKEN). Must already be "
                "on Hermes's known credential list — the same list the "
                "dashboard's Keys & Environment page manages. Unknown names "
                "are refused."
            ),
        },
        "reason": {
            "type": "string",
            "description": (
                "One short sentence explaining to the user why this "
                "credential is needed right now."
            ),
        },
    },
    "required": ["env_var"],
}


def _known_env_vars() -> dict:
    from hermes_cli.config import OPTIONAL_ENV_VARS, REQUIRED_ENV_VARS

    merged: dict = {}
    merged.update(REQUIRED_ENV_VARS)
    merged.update(OPTIONAL_ENV_VARS)
    return merged


def _handle_request_credential(args: dict, **kwargs) -> str:
    try:
        from hermes_cli.config import get_env_value

        env_var = str(args.get("env_var") or "").strip().upper()
        reason = str(args.get("reason") or "").strip()

        if not env_var:
            return json.dumps({"error": "env_var is required"})

        known = _known_env_vars()
        info = known.get(env_var)
        if info is None:
            return json.dumps({
                "error": (
                    f"'{env_var}' is not on Hermes's known credential list "
                    "(the same allowlist the dashboard's Keys & Environment "
                    "page is built from). Refusing to send the user there — "
                    "double-check the exact variable name; if it's correct, "
                    "this isn't a credential Hermes manages this way."
                ),
            })

        is_set = bool(get_env_value(env_var))
        label = info.get("description") or env_var

        message = (
            f"Tell the user: open Mission Control → Keys & Environment, "
            f"find {env_var} ({label}), and paste the value directly into "
            "that field. It goes straight from their browser to the "
            "server's .env file — it never passes through this "
            "conversation, this model, or any log."
        )
        if reason:
            message += f" Why it's needed: {reason}"
        message += (
            " Once they say it's done, call request_credential again with "
            "the same env_var to confirm — you'll only get true/false back, "
            "never the value itself."
        )

        return json.dumps({
            "env_var": env_var,
            "is_set": is_set,
            "label": label,
            "message": message,
        })
    except Exception as exc:  # tools must never raise — return error JSON
        logger.exception("request_credential failed")
        return json.dumps({"error": f"request_credential failed: {exc}"})


def register(ctx) -> None:
    """Register the request_credential tool. Called once by the plugin loader."""
    ctx.register_tool(
        name="request_credential",
        toolset="credential_handoff",
        schema=REQUEST_CREDENTIAL_SCHEMA,
        handler=_handle_request_credential,
        description=(
            "Ask the user to enter an API key or other credential through "
            "the Mission Control dashboard's Keys & Environment page rather "
            "than in chat. Reports only whether it's already set "
            "(true/false) plus instructions to relay — the plaintext value "
            "never reaches this tool, the model, or any transcript."
        ),
        emoji="\U0001F511",
    )
    logger.debug("credential-handoff: registered request_credential tool")
