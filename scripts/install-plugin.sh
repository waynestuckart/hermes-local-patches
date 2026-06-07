#!/usr/bin/env bash
# Install a plugin from this repo into ~/.hermes/plugins/.
#
# Unlike the source-tree patches in patches/, plugins don't need re-apply
# machinery: ~/.hermes/plugins/ is a separate directory `hermes update`
# never touches. We just need it there once. Default is a symlink, so
# edits made here show up after a `/plugins reload` or gateway restart;
# pass --copy for a standalone copy instead.
#
# Usage: ./scripts/install-plugin.sh <plugin-name> [--copy]
#
# Override the destination with HERMES_PLUGINS_DIR (default: ~/.hermes/plugins)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_DIR="${HERMES_PLUGINS_DIR:-$HOME/.hermes/plugins}"

name="${1:-}"
mode="${2:-}"

if [ -z "$name" ]; then
  echo "usage: $(basename "$0") <plugin-name> [--copy]" >&2
  echo "available plugins:" >&2
  for d in "$REPO_DIR"/plugins/*/; do
    [ -f "$d/plugin.yaml" ] && echo "  - $(basename "$d")" >&2
  done
  exit 1
fi

src="$REPO_DIR/plugins/$name"
dest="$PLUGINS_DIR/$name"

[ -f "$src/plugin.yaml" ] || { echo "✗ no such plugin: $src" >&2; exit 1; }
mkdir -p "$PLUGINS_DIR"

if [ -e "$dest" ] || [ -L "$dest" ]; then
  echo "✗ $dest already exists — remove it first if you want to reinstall" >&2
  exit 1
fi

if [ "$mode" = "--copy" ]; then
  cp -r "$src" "$dest"
  echo "✓ copied $name → $dest"
else
  ln -s "$src" "$dest"
  echo "✓ symlinked $name → $dest"
fi

cat <<EOF

Restart the gateway (or run \`/plugins reload\` in a session) so it loads:
  systemctl --user restart hermes-gateway.service
EOF
