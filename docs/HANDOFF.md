# Handoff — API keys getting mangled in Hermes

**Status:** fix written, pushed, and on a draft PR. Not yet verified against a
live agent loop. **One manual round-trip test is recommended before relying on it.**

- Branch: `claude/hermes-api-key-truncation-CBiNw`
- PR: https://github.com/waynestuckart/hermes-local-patches/pull/4 (draft)
- Patches added: `patches/0002-secret-prompt-paste-no-truncate.patch`,
  `patches/0003-no-redact-tool-call-args.patch`

---

## The problem (as reported)

Entering an API key for Hermes — even short, normal keys (`sk-or-…`, `sk-ant-…`,
a Telegram bot token) — produced a corrupted value, so keys had to be set by
hand-written scripts. Concrete failures:

- `write_file` of JSON → key replaced mid-string → broken JSON
- `terminal` → `KEY=sk-or-…` became `KEY=***` → empty bash variable
- Python heredoc → key string literal broken → `SyntaxError`

## Root cause

**Hermes's secret redactor (`agent/redact.py`) was masking the agent's own
tool-call _arguments_ before they re-entered conversation history.** The model
authored those arguments, so masking them hides nothing from it — it only
corrupts the model's view of its own prior call on the next turn. Sites:

| File | Line(s) | What it did |
|------|---------|-------------|
| `agent/chat_completion_helpers.py` | 987 | Masked the **persisted** tool-call args replayed verbatim next turn (the #19798 "defence-in-depth"). |
| `agent/context_compressor.py` | 981, 1056 | Same, in the compression/summary path (also broke `json.loads` of the args). |

Reproduced against the live redactor:

```
write_file JSON     {"api_key": "sk-or-v1-…"}   →  {"api_key": "***"}        broken JSON
bash assignment     OPENROUTER_API_KEY=sk-or-…   →  OPENROUTER_API_KEY=***    empty var
python literal      key = "sk-or-v1-…"           →  key = "sk-or-...6789"     SyntaxError
telegram bot token  TG=8518135530:AA…            →  TG=8518135530:***
```

This was **not** Telegram and **not** the message-input path — inbound text is
passed through in full (`gateway/platforms/telegram.py:_build_message_event`,
`text = message.text or ""`).

## The fix

### `0003-no-redact-tool-call-args.patch` (primary)

Keeps **tool-call arguments verbatim** at the three sites above.

- **Still redacted (unchanged):** tool **output** (`tools/terminal_tool.py`,
  file reads/searches in `tools/file_tools.py`) and **logs**
  (`RedactingFormatter`). Secrets still don't leak into logs or the gateway
  console.
- **Tradeoff (chosen deliberately):** a secret the agent inlines into a tool
  call now stays in the context sent to the model provider on later turns.
  Accepted in exchange for keys that work. To restore the old behavior, just
  drop this patch — `security.redact_secrets` stays at its default `true`.

### `0002-secret-prompt-paste-no-truncate.patch` (adjacent, not the root cause)

Hardens the masked CLI prompt every `hermes` key/token entry uses
(`hermes_cli/secret_prompt.py`). It read the terminal in raw mode and treated any
`\r`/`\n` as Enter, so a pasted key with a trailing newline (or wrapped across
lines) submitted early and kept only the part before the first newline (leaking
the rest to the shell). The patch enables **bracketed paste**, treats newlines
inside a paste as content, and strips the result → key lands on one clean line.

---

## Deploy

```bash
cd hermes-local-patches
export HERMES_AGENT_DIR="$HOME/.hermes/hermes-agent"   # adjust if different
./scripts/install.sh                                   # copies + applies both patches
systemctl --user restart hermes-gateway.service        # reload code (Hermes holds code in memory)
```

`apply.sh` is idempotent: it skips patches already present and re-applies after
every `hermes update` via the git `post-merge` / `post-rewrite` hooks.

## Verify (do this before trusting it)

1. **Live round-trip (most important):** ask the agent to write a real key to
   `~/.hermes/.env` and read it back, or set a provider key and confirm a call
   succeeds. The key should be byte-for-byte intact across turns.
2. Patches apply clean / reverse-clean on a pristine checkout:
   ```bash
   cd "$HERMES_AGENT_DIR"
   git apply --check  /path/to/patches/0003-no-redact-tool-call-args.patch   # clean apply
   git apply /path/to/patches/0003-no-redact-tool-call-args.patch
   git apply --reverse --check /path/to/patches/0003-no-redact-tool-call-args.patch  # idempotent
   git checkout agent/chat_completion_helpers.py agent/context_compressor.py
   ```
3. Confirm redaction of tool **output**/logs still works (e.g. `cat` a file
   containing a `sk-…` key in a terminal tool call → should still show masked in
   the returned output).

## Done / outstanding

- [x] Root cause identified (redactor on tool-call args, not input/Telegram)
- [x] Fix written for the chosen approach (keep tool-call args verbatim)
- [x] Corruption reproduced + removal confirmed; patches parse and apply clean
- [x] CLI paste-prompt bug also patched (`0002`)
- [x] Pushed; draft PR #4 open
- [ ] **Live agent round-trip test** (write a real key, read it back)
- [ ] Merge PR, run `./scripts/install.sh`, restart gateway
- [ ] (Optional) send `0002` / `0003` upstream to `NousResearch/hermes-agent`;
      once merged they become no-ops and `apply.sh` skips them

## Upstream references touched

- `agent/redact.py` — the redactor (unchanged; understanding only)
- `agent/chat_completion_helpers.py`, `agent/context_compressor.py` — patched by `0003`
- `hermes_cli/secret_prompt.py` — patched by `0002`
- #19798 — the upstream change that introduced the arg-redaction `0003` reverses
