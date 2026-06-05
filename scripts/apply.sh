#!/usr/bin/env bash
# Re-apply Wayne's local Hermes modifications after a `hermes update` / git pull.
#
# Why this exists: `hermes update` runs `git pull --ff-only` (or, when history
# diverges, `git reset --hard origin/main`), either of which discards local
# source edits. These patches live OUTSIDE the repo (in $HERMES_HOME) so the
# update can't touch them, and this script re-applies any that aren't already
# present. It is idempotent and safe to run repeatedly.
#
# Invoked automatically by the git post-merge / post-rewrite hooks, and can be
# run by hand any time:  bash ~/.hermes/local-patches/apply.sh
set -euo pipefail

REPO="${HERMES_AGENT_DIR:-$HOME/.hermes/hermes-agent}"
PATCH_DIR="${HERMES_PATCH_DIR:-$HOME/.hermes/local-patches}"

cd "$REPO" || { echo "[local-patches] repo not found: $REPO" >&2; exit 0; }

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
  echo "[local-patches] no patches in $PATCH_DIR — nothing to do"
  exit 0
fi

applied=0 skipped=0 failed=0
for p in "${patches[@]}"; do
  name="$(basename "$p")"
  # Already present? `--reverse --check` succeeds only if the patch is fully applied.
  if git apply --reverse --check "$p" >/dev/null 2>&1; then
    echo "[local-patches] ✓ already applied: $name"
    skipped=$((skipped+1))
    continue
  fi
  # Cleanly applicable to current tree?
  if git apply --check "$p" >/dev/null 2>&1; then
    git apply "$p"
    echo "[local-patches] ✓ applied: $name"
    applied=$((applied+1))
  else
    echo "[local-patches] ✗ CONFLICT, could not apply: $name" >&2
    echo "                upstream likely changed the same lines — reconcile manually:" >&2
    echo "                cd $REPO && git apply --3way '$p'" >&2
    failed=$((failed+1))
  fi
done

echo "[local-patches] done — applied=$applied skipped=$skipped failed=$failed"
[ "$failed" -eq 0 ]
