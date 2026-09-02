#!/usr/bin/env bash
# Installs the app into Elten 3 as an UNBUILT source folder
# (apps/src/MileByMile). Elten 3 loads folder apps directly in developer
# mode — no packaging needed. For a signed release Dawid bundles the app
# himself, so this script is all we need for daily iteration.
#
# Usage: sh install_elten.sh
# Works on Windows (Git Bash) and Linux.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MileByMile"
SRC="src"

# the engine lives as a copy inside src/ — sync it before installing
sh sync_engine.sh >/dev/null

# Elten keeps programs in <appdata>/elten/apps/src
if [ -n "${APPDATA:-}" ]; then
  APPS_DIR="$APPDATA/elten/apps/src"            # Windows (Git Bash)
elif [ -n "${XDG_DATA_HOME:-}" ]; then
  APPS_DIR="$XDG_DATA_HOME/elten/apps/src"      # Linux
else
  APPS_DIR="$HOME/.local/share/elten/apps/src"
fi

if [ -z "$APPS_DIR" ] || [ "$APPS_DIR" = "/" ]; then
  echo "Cannot locate Elten apps dir" >&2
  exit 1
fi

# (re)build .mo from .po when a translation source is newer than its .mo
RUBY="$(command -v ruby || command -v ruby3.3 || true)"
if [ -n "$RUBY" ]; then
  for po in "$SRC"/locale/*.po; do
    [ -e "$po" ] || continue
    mo="${po%.po}.mo"
    if [ ! -e "$mo" ] || [ "$po" -nt "$mo" ]; then
      if "$RUBY" tools/po2mo.rb "$po" "$mo"; then
        :
      else
        echo "warning: could not rebuild $mo — copying the existing one" >&2
      fi
    fi
  done
else
  echo "warning: ruby not found — .mo not rebuilt, locale/*.mo copied as-is" >&2
fi

DEST="$APPS_DIR/$APP_NAME"
rm -rf "$DEST"
mkdir -p "$APPS_DIR"
cp -r "$SRC" "$DEST"
rm -f "$DEST/README.md"

# Elten 3.0.1's Elten3AppInfo parser chokes on CRLF: the closing marker
# regex misses a trailing \r and the program shows as "incompatible".
# Git for Windows checks out with CRLF by default, so force LF on install.
if command -v sed >/dev/null 2>&1; then
  find "$DEST" -type f \( -name '*.rb' -o -name '*.json' -o -name '*.po' \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true
else
  echo "warning: sed not found — CRLF not normalized, Elten may flag the app as incompatible" >&2
fi

echo "Installed $APP_NAME -> $DEST"
echo "Restart Elten (Выход → Перезагрузить) to pick it up."
