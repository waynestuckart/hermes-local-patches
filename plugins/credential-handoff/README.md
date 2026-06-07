# credential-handoff

Gives Hermes a safe way to ask you for an API key without ever seeing it.

## The problem this solves

Hermes won't take secrets in chat — for good reason: conversation turns are
sent to the model provider and persisted to logs/transcripts, so a key typed
there is effectively burned the moment you send it. Its fallback is "go edit
`~/.hermes/.env` in a terminal", which assumes you're at a machine with one.

But Mission Control (the web dashboard) already has the right mechanism: its
**Keys & Environment** page writes credentials straight from your browser to
the server's `.env` file via `PUT /api/env` — no LLM call anywhere on that
path. The plaintext never becomes part of a prompt, a tool result, or a log
line.

This plugin adds one tool, `request_credential`, that teaches Hermes to use
that path:

1. Hermes calls `request_credential(env_var, reason)`.
2. The tool reports whether the variable is **already set** — a bare
   `true`/`false`, never the value — plus instructions for Hermes to relay
   to you.
3. You open **Mission Control → Keys & Environment**, find the field, and
   paste the key in yourself.
4. Hermes calls `request_credential` again, sees `is_set: true`, and
   continues — having never touched the plaintext.

## Guardrail

`request_credential` only accepts environment-variable names that are
already on Hermes's known credential list (`REQUIRED_ENV_VARS` /
`OPTIONAL_ENV_VARS` in `hermes_cli/config.py` — the exact same list the
dashboard's Keys page is generated from). Anything else — `LD_PRELOAD`, a
sudo password, `PATH`, a made-up name — is refused outright, so a confused
or adversarial model turn can't steer you into pasting something sensitive
into a field that was never meant to hold it.

## Install

```bash
cd /path/to/hermes-local-patches
./scripts/install-plugin.sh credential-handoff
```

This symlinks the plugin into `~/.hermes/plugins/credential-handoff` (pass
`--copy` for a standalone copy instead). Restart the gateway, or run
`/plugins reload` in a session, to pick it up:

```bash
systemctl --user restart hermes-gateway.service
```

Verify it loaded:

```
/plugins
```

```
Plugins (1):
  ✓ credential-handoff v1.0.0 (1 tools, 0 hooks)
```

## Try it

> "I need to set up Spotify — what do you need from me?"

Hermes should now call `request_credential` and point you at Mission
Control instead of asking you to paste anything into the chat.
