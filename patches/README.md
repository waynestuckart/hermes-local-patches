# patches/

Each `*.patch` is a `git diff` snapshot of a local modification to the Hermes
Agent source tree. They're stored here, **outside** the `hermes-agent` checkout,
so `hermes update` (which runs `git pull` / `git reset --hard`) can't remove
them. `../scripts/apply.sh` re-applies any that aren't already present.

## Current patches

- **`0001-model-picker-billing-tags.patch`** — adds `[pay]`/`[sub]`/`[oauth]`/
  `[local]` billing tags to the `/model` picker (CLI + Telegram). Upstreamed as
  NousResearch/hermes-agent PR #39403; becomes a no-op once that merges.
- **`0002-secret-prompt-paste-no-truncate.patch`** — stops the masked API-key
  prompt (`hermes_cli/secret_prompt.py`, used by every `hermes` key/token entry)
  from truncating pasted secrets. The raw-mode reader treated a `\r`/`\n` inside
  a paste — a key copied with a trailing newline, or one wrapped across lines —
  as Enter, submitting only the part before the first newline (and leaking the
  rest to the shell). The patch enables bracketed paste, drops newlines that
  arrive inside a paste, and strips the result, so the key always lands on one
  clean, un-truncated line.

## Add your own

```bash
cd "$HERMES_AGENT_DIR"        # e.g. ~/.hermes/hermes-agent
# ...edit source...
git diff <files> > /path/to/patches/0002-my-change.patch
```

Patches apply in filename order. Keep them small and focused so conflicts after
an upstream change are easy to reconcile (`git apply --3way`).
