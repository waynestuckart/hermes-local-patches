# hermes-local-patches

Keep local source modifications to a [Hermes Agent](https://github.com/NousResearch/hermes-agent)
install alive across `hermes update` — plus two worked examples: **billing-model
tags** (`[pay]` / `[sub]` / `[oauth]` / `[local]`) in the `/model` picker, and a
friendlier provider label when Hermes runs routed through
[NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw).

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

## Worked example: NemoClaw routed-provider label

When Hermes runs inside an [NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw)
OpenShell sandbox (`nemohermes`), NemoClaw points `model.base_url` at its
host-side router, `https://inference.local/v1`, with `model.provider: custom` —
so real provider credentials never enter the sandbox. Stock Hermes has no idea
what `inference.local` is, so `hermes status` and the `/model` picker just show
the generic `Custom endpoint` label, which makes it hard to tell at a glance
that you're running through NemoClaw at all.

`patches/0002-nemoclaw-routed-provider-label.patch` adds a small
`_is_nemoclaw_routed_endpoint()` check to `hermes_cli/models.py`: when the
`custom` endpoint's host is `inference.local`, `provider_label()` returns
`NemoClaw (routed)` instead.

```
Before:  Provider:     Custom endpoint
After:   Provider:     NemoClaw (routed)
```

## Repo layout

```
patches/    0001-model-picker-billing-tags.patch
            0002-nemoclaw-routed-provider-label.patch
            + a README on the patch system
scripts/    apply.sh (idempotent re-applier)  ·  install.sh (wires hooks)
hooks/      post-merge, post-rewrite           (installed into .git/hooks/)
docs/       SURVIVE-UPDATES.md                 (the pattern, in depth)
```

## Adding your own patch

```bash
cd "$HERMES_AGENT_DIR"
# ...make your edits...
git diff <files> > /path/to/hermes-local-patches/patches/0003-my-change.patch
```

`apply.sh` picks up every `*.patch` in the patch dir, in name order.

## License

MIT — see [LICENSE](LICENSE).
