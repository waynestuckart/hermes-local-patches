# patches/

Each `*.patch` is a `git diff` snapshot of a local modification to the Hermes
Agent source tree. They're stored here, **outside** the `hermes-agent` checkout,
so `hermes update` (which runs `git pull` / `git reset --hard`) can't remove
them. `../scripts/apply.sh` re-applies any that aren't already present.

## Current patches

- **`0001-model-picker-billing-tags.patch`** — adds `[pay]`/`[sub]`/`[oauth]`/
  `[local]` billing tags to the `/model` picker (CLI + Telegram). Upstreamed as
  NousResearch/hermes-agent PR #39403; becomes a no-op once that merges.
- **`0002-nemoclaw-routed-provider-label.patch`** — when Hermes runs inside an
  [NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw) OpenShell sandbox,
  `model.base_url` is set to NemoClaw's host-side router at
  `https://inference.local/v1` and `model.provider` is the generic `custom`.
  `hermes status` / the picker then just say `Custom endpoint`, hiding the
  fact that traffic is routed and credentials are managed by NemoClaw. This
  patch detects the `inference.local` host and labels it `NemoClaw (routed)`
  instead.

## Add your own

```bash
cd "$HERMES_AGENT_DIR"        # e.g. ~/.hermes/hermes-agent
# ...edit source...
git diff <files> > /path/to/patches/0002-my-change.patch
```

Patches apply in filename order. Keep them small and focused so conflicts after
an upstream change are easy to reconcile (`git apply --3way`).
