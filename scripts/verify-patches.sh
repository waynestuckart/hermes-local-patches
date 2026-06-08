#!/usr/bin/env bash
# Dry-run every patch and confirm it still applies cleanly to a Hermes Agent
# tree — and that the patched Python is still valid. Run this BEFORE
# `hermes update`, or let CI run it on a schedule, so you find out the day
# upstream changes the same lines a patch touches (or upstreams the feature)
# instead of discovering it mid-update.
#
#   bash scripts/verify-patches.sh
#
# Modes:
#   * HERMES_AGENT_DIR set  → checks against your real checkout (non-destructive:
#                             --check only, never touches your working tree).
#   * HERMES_AGENT_DIR unset→ clones upstream fresh and runs the FULL check,
#                             including applying + py_compile in the throwaway.
#
# Env:
#   HERMES_PATCH_DIR     (default: <repo>/patches)
#   HERMES_AGENT_DIR     (default: clone upstream)
#   HERMES_UPSTREAM_URL  (default: https://github.com/NousResearch/hermes-agent)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="${HERMES_PATCH_DIR:-$here/patches}"
UPSTREAM_URL="${HERMES_UPSTREAM_URL:-https://github.com/NousResearch/hermes-agent}"
REPO="${HERMES_AGENT_DIR:-}"

tmproot=""
if [ -z "$REPO" ]; then
  tmproot="$(mktemp -d)"
  REPO="$tmproot/hermes-agent"
  echo "[verify] HERMES_AGENT_DIR unset — cloning upstream: $UPSTREAM_URL"
  git clone --depth 1 "$UPSTREAM_URL" "$REPO" >/dev/null 2>&1
fi
trap '[ -n "$tmproot" ] && rm -rf "$tmproot"' EXIT

cd "$REPO"
echo "[verify] tree: $REPO @ $(git log -1 --format='%h %ci' 2>/dev/null || echo 'non-git')"

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
if [ ${#patches[@]} -eq 0 ]; then echo "[verify] no patches in $PATCH_DIR"; exit 0; fi

fail=0 clean=()
for p in "${patches[@]}"; do
  name="$(basename "$p")"
  if git apply --reverse --check "$p" >/dev/null 2>&1; then
    echo "[verify] ✓ already applied (live tree): $name"; clean+=("$p"); continue
  fi
  if git apply --check "$p" >/dev/null 2>&1; then
    echo "[verify] ✓ applies cleanly: $name"; clean+=("$p")
  else
    echo "[verify] ✗ DOES NOT APPLY: $name — upstream changed the same lines (or the feature merged)."
    git apply --check "$p" 2>&1 | sed 's/^/           /' || true
    fail=1
  fi
done

# Full validation (apply + compile) only in the throwaway clone, so we never
# mutate the user's real working tree.
if [ "$fail" -eq 0 ] && [ -n "$tmproot" ]; then
  for p in "${clean[@]}"; do git apply --reverse --check "$p" >/dev/null 2>&1 || git apply "$p"; done
  mapfile -t pyfiles < <(grep -hE '^\+\+\+ b/.*\.py$' "${patches[@]}" | sed 's#^+++ b/##' | sort -u)
  if [ ${#pyfiles[@]} -gt 0 ]; then
    echo "[verify] py_compile: ${pyfiles[*]}"
    if python3 -m py_compile "${pyfiles[@]}"; then
      echo "[verify] ✓ patched Python compiles"
    else
      echo "[verify] ✗ py_compile FAILED after applying patches"; fail=1
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "[verify] ALL GOOD — safe to update"
else
  echo "[verify] FAILURES — reconcile a patch before you run \`hermes update\`:"
  echo "         cd \"\$HERMES_AGENT_DIR\" && git apply --3way '<patch>'   # then re-diff into patches/"
fi
exit "$fail"
