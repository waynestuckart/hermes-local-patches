# hermes-local-patches

Keep local source modifications to a [Hermes Agent](https://github.com/NousResearch/hermes-agent)
install alive across `hermes update` — plus a couple of worked examples: **billing-model
tags** (`[pay]` / `[sub]` / `[oauth]` / `[local]`) in the `/model` picker, and a
**credential-handoff plugin** that lets Hermes ask for API keys without ever seeing them.

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

## Worked example: handing Hermes an API key without her seeing it

Hermes (sensibly) refuses to take secrets in chat — conversation turns get sent
to the model provider and persisted to transcripts/logs, so a key typed there is
burned the moment you send it. Her fallback — "go edit `~/.hermes/.env` in a
terminal" — assumes you're at a machine with one.

But Mission Control (the web dashboard) already has the right plumbing: its
**Keys & Environment** page writes credentials straight from your browser to
`.env` via `PUT /api/env`, with no LLM call anywhere on that path. The plaintext
never enters a prompt, a tool result, or a log line.

`plugins/credential-handoff/` adds one tool, `request_credential`, that teaches
Hermes to use that path: she asks for a credential by **name only**, gets back a
bare `is_set: true/false` (never the value) plus instructions to relay, and you
paste the key into Mission Control yourself. She then re-checks `is_set` and
carries on — having never touched the plaintext. Only names already on Hermes's
known credential allowlist can be requested, so a confused model turn can't steer
you into pasting something sensitive into the wrong field.

Unlike the patches above, plugins live in `~/.hermes/plugins/` — a directory
`hermes update` never touches — so this needs no patch-survival machinery, just
a one-time install:

```bash
./scripts/install-plugin.sh credential-handoff
```

See [plugins/credential-handoff/README.md](plugins/credential-handoff/README.md)
for details.

## Repo layout

```
patches/    0001-model-picker-billing-tags.patch  + a README on the patch system
plugins/    credential-handoff/                   (blind credential request tool)
scripts/    apply.sh ・ install.sh ・ install-plugin.sh
hooks/      post-merge, post-rewrite               (installed into .git/hooks/)
docs/       SURVIVE-UPDATES.md                     (the pattern, in depth)
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
