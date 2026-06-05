# Surviving `hermes update` — the pattern in depth

## Why local edits vanish

`~/.hermes/hermes-agent/` is a git checkout of `NousResearch/hermes-agent`. The
updater (`hermes_cli/main.py`) does, in order:

1. Auto-stash any dirty working-tree changes.
2. `git pull --ff-only origin main`.
3. If that fails (history diverged — upstream force-push/rebase):
   `git reset --hard origin/<branch>`.
4. On success, restore the auto-stash (3-way merge; may conflict).

Consequences for anyone hand-editing the source:

- **Uncommitted edits** → auto-stashed, then re-applied via 3-way merge. Works
  until upstream touches the same lines, then you get stash conflicts.
- **A local commit on `main`** → blocks the ff-only pull, forces the
  `reset --hard`, and is **wiped** (no hook fires on reset).

Neither is durable on its own. Hence: keep changes as patch files *outside* the
repo and re-apply them deterministically.

## The three layers

### 1. git hooks (primary, automatic)

`.git/hooks/post-merge` and `.git/hooks/post-rewrite` call `apply.sh`. They fire
after the `git pull` that `hermes update` runs. `.git/hooks/` is **not tracked**
and is never modified by `pull` or `reset --hard`, so the hooks themselves
survive every update.

```sh
#!/usr/bin/env bash
# .git/hooks/post-merge — non-fatal: never block the merge on a patch conflict
bash "$HOME/.hermes/local-patches/apply.sh" || true
```

Gap: the `git reset --hard` divergence path fires **no** hook.

### 2. manual (escape hatch)

```bash
bash ~/.hermes/local-patches/apply.sh
```

Idempotent. Run it whenever you're unsure — it reports `applied`/`skipped`/`failed`.

### 3. systemd `ExecStartPre` (optional hardening)

Covers the `reset --hard` gap: you must restart the gateway to load new code
anyway, so re-applying patches on every start guarantees they're present
regardless of how the update mutated the tree.

```ini
[Service]
# leading '-' = non-fatal: a patch conflict must not block the gateway
ExecStartPre=-/usr/bin/bash %h/.hermes/local-patches/apply.sh
ExecStart=...
```

```bash
systemctl --user daemon-reload
```

This layer is optional and environment-specific (only if you run the gateway
under systemd). The git hooks cover the common case on their own.

## Why `apply.sh` is idempotent

```sh
# already present?  --reverse --check succeeds only if the patch is fully applied
if git apply --reverse --check "$p"; then skip; fi
# cleanly applicable?
if git apply --check "$p"; then git apply "$p"; else warn_conflict; fi
```

So running it twice is a no-op, and running it after an update applies exactly
what the update removed.

## When a patch conflicts

Upstream changed the same lines. Reconcile with a 3-way apply, then refresh the
patch so it's clean again:

```bash
cd ~/.hermes/hermes-agent
git apply --3way ~/.hermes/local-patches/0001-foo.patch
# resolve any <<<< markers, then:
git diff > ~/.hermes/local-patches/0001-foo.patch
```

## The real fix: upstream it

Patches are a bridge, not a destination. The durable answer is to get your change
merged upstream — then it ships with every `hermes update` and the patch becomes a
no-op `apply.sh` skips. The billing-tags example here is upstreamed as
[NousResearch/hermes-agent #39403](https://github.com/NousResearch/hermes-agent/pull/39403).
