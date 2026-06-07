# hermes-local-patches

Keep local source modifications to a [Hermes Agent](https://github.com/NousResearch/hermes-agent)
install alive across `hermes update` — and a worked example that adds **billing-model
tags** (`[pay]` / `[sub]` / `[oauth]` / `[local]`) to the `/model` picker.

---

## The problem

Hermes Agent is a git checkout. `hermes update` runs `git pull --ff-only`, or
`git reset --hard origin/main` when history diverges. **Both discard local edits
to the source tree.** If you've tweaked anything under `hermes-agent/`, the next
update silently wipes it. Committing on `main` is worse — it makes the ff-only
pull fail and triggers the hard reset.

## The solution

Keep your changes as **patch files stored outside the repo** (so updates can't
touch them) and re-apply them automatically after every update. Two automatic
layers, plus a manual escape hatch:

1. **git `post-merge` + `post-rewrite` hooks** — fire after `hermes update`'s
   `git pull`. Hooks live in `.git/hooks/`, which is untracked and never
   overwritten by pull/reset.
2. **manual** — `apply.sh` any time. Idempotent: it skips patches already
   present and only applies what's missing.
3. *(optional hardening)* a systemd `ExecStartPre` that runs `apply.sh` before
   the gateway starts — covers the rare `reset --hard` path, which fires no git
   hook. See [docs/SURVIVE-UPDATES.md](docs/SURVIVE-UPDATES.md).

`apply.sh` is safe to run repeatedly and warns (non-fatally) if a patch no longer
applies cleanly because upstream changed the same lines.

## Quick start

```bash
git clone https://github.com/<you>/hermes-local-patches
cd hermes-local-patches

# Point at your Hermes checkout (default: ~/.hermes/hermes-agent)
export HERMES_AGENT_DIR="$HOME/.hermes/hermes-agent"

# Install the git hooks and copy the patches into place
./scripts/install.sh

# Apply now
HERMES_PATCH_DIR="$PWD/patches" ./scripts/apply.sh
```

Then restart the gateway so the new code loads (Hermes holds code in memory):

```bash
systemctl --user restart hermes-gateway.service   # or however you run it
```

## Worked example: billing tags in the `/model` picker

The picker never told you whether a provider bills **metered API credits** or a
**flat subscription**. In the CLI it was only implied by the description; in the
Telegram inline-keyboard picker it was invisible. Easy to burn credits on a model
you already have a subscription for elsewhere.

`patches/0001-model-picker-billing-tags.patch` adds a compact tag everywhere the
picker shows a provider or model:

| Tag | Meaning |
|-----|---------|
| `[pay]` | metered API credits (per-token / per-request) |
| `[sub]` | flat subscription / coding plan |
| `[oauth]` | OAuth login (subscription or free tier behind it) |
| `[local]` | runs on-device, no provider billing |

```
Provider families:   OpenCode [pay/sub]   MiniMax [pay/sub]   Anthropic [pay]
  drill in:          OpenCode Zen [pay]    OpenCode Go [sub]
  model buttons:     claude-sonnet-4-6 [pay]   ·   (via Go) glm-5.1 [sub]
```

Same model shows `[pay]` reached through one plan and `[sub]` through another.

It's driven by a single `PROVIDER_BILLING` map (`hermes_cli/models.py`) so adding
a provider is one line. **This feature is upstreamed** as
[NousResearch/hermes-agent #39403](https://github.com/NousResearch/hermes-agent/pull/39403);
once it merges, the patch becomes a no-op and `apply.sh` simply skips it.

## Fix: pasted API keys no longer get truncated

`patches/0002-secret-prompt-paste-no-truncate.patch` fixes the masked secret
prompt that **every** `hermes` API-key / token entry goes through
(`hermes_cli/secret_prompt.py` — the "hidden, can't-see-it" input).

The prompt reads the terminal in raw mode and treated any carriage return or
newline as **Enter**. When you paste a key that carries a trailing newline (most
copies do) or one that's wrapped across lines, the embedded newline submitted the
prompt early — Hermes kept only the text **before** the first newline and the rest
spilled onto the shell. The key looked "truncated," so you ended up exporting it
by hand in a script.

The patch turns on the terminal's **bracketed-paste** mode and treats newlines
that arrive *inside a paste* as part of the secret (flattening them away) rather
than as Enter, then strips the result. A real Enter keypress still submits. Net
effect: a pasted key always lands on **one clean line, in full** —

```
  API key (sk-ant-...): ****************************************   ← whole key captured
```

No upstream PR yet; it's a candidate to send to `hermes-agent`.

## Fix: API keys no longer corrupted when the agent handles them

`patches/0003-no-redact-tool-call-args.patch` fixes the *other* place keys got
mangled — not on input, but when the **agent** stores or uses one for you.

Hermes's secret redactor (`agent/redact.py`) was masking the arguments of the
agent's **own tool calls** before they re-entered conversation history
(`agent/chat_completion_helpers.py`, `agent/context_compressor.py`). So when the
agent ran `write_file`, `terminal`, or a Python heredoc with a key in it, the
*next* turn replayed that call with the key swapped for `***`:

```
write_file JSON     {"api_key": "sk-or-v1-…"}     →  {"api_key": "***"}        broken JSON
bash assignment     OPENROUTER_API_KEY=sk-or-…     →  OPENROUTER_API_KEY=***    empty var
python literal      key = "sk-or-v1-…"             →  key = "sk-or-...6789"     SyntaxError
```

The model wrote those arguments itself, so masking them in history hides nothing
from it — it only corrupts the model's view of its own prior call, which is why
the value came out broken and you ended up scripting around it. The patch keeps
**tool-call arguments verbatim**. Secret masking of tool **output** (a `cat` of a
`.env`, command stdout) and of **logs** is untouched, so secrets still don't leak
into logs or the gateway console.

> Tradeoff: a secret the agent inlines into a tool call now stays in the context
> that's sent to the model provider on later turns. That's accepted here in
> exchange for keys that actually work — flip it back with
> `security.redact_secrets: true` (the default) if you remove this patch.

No upstream PR yet; it's a candidate to send to `hermes-agent`.

## Repo layout

```
patches/    0001-model-picker-billing-tags.patch
            0002-secret-prompt-paste-no-truncate.patch
            0003-no-redact-tool-call-args.patch          + a README on the patch system
scripts/    apply.sh (idempotent re-applier)  ·  install.sh (wires hooks)
hooks/      post-merge, post-rewrite           (installed into .git/hooks/)
docs/       SURVIVE-UPDATES.md                 (the pattern, in depth)
```

## Adding your own patch

```bash
cd "$HERMES_AGENT_DIR"
# ...make your edits...
git diff <files> > /path/to/hermes-local-patches/patches/0002-my-change.patch
```

`apply.sh` picks up every `*.patch` in the patch dir, in name order.

## License

MIT — see [LICENSE](LICENSE).
