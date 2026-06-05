#!/usr/bin/env bash
# Install the local-patches system into a Hermes Agent checkout:
#   1. copy patch files into the patch dir (outside the repo)
#   2. install git post-merge / post-rewrite hooks that re-apply them
#   3. apply them once now
#
# Override locations with env vars:
#   HERMES_AGENT_DIR  (default: ~/.hermes/hermes-agent)
#   HERMES_PATCH_DIR  (default: ~/.hermes/local-patches)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="${HERMES_AGENT_DIR:-$HOME/.hermes/hermes-agent}"
PATCH_DIR="${HERMES_PATCH_DIR:-$HOME/.hermes/local-patches}"

[ -d "$AGENT_DIR/.git" ] || { echo "✗ $AGENT_DIR is not a git checkout" >&2; exit 1; }

echo "→ Hermes checkout: $AGENT_DIR"
echo "→ Patch dir:       $PATCH_DIR"

# 1. patches + apply.sh into the patch dir (outside the repo, update-safe)
mkdir -p "$PATCH_DIR"
cp "$REPO_DIR"/patches/*.patch "$PATCH_DIR"/
cp "$REPO_DIR"/scripts/apply.sh "$PATCH_DIR"/apply.sh
chmod +x "$PATCH_DIR"/apply.sh
echo "✓ copied $(ls "$REPO_DIR"/patches/*.patch | wc -l) patch(es) + apply.sh"

# 2. git hooks
HOOKS="$AGENT_DIR/.git/hooks"
for h in post-merge post-rewrite; do
  install -m 0755 "$REPO_DIR/hooks/$h" "$HOOKS/$h"
done
echo "✓ installed post-merge + post-rewrite hooks"

# 3. apply now
HERMES_PATCH_DIR="$PATCH_DIR" HERMES_AGENT_DIR="$AGENT_DIR" bash "$PATCH_DIR/apply.sh"

cat <<EOF

Done. Restart the gateway so the new code loads:
  systemctl --user restart hermes-gateway.service

Optional hardening (covers the 'git reset --hard' update path): add to your
gateway's systemd unit, then \`systemctl --user daemon-reload\`:
  ExecStartPre=-/usr/bin/bash $PATCH_DIR/apply.sh
EOF
