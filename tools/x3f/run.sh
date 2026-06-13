#!/usr/bin/env bash
# Launch the dev-built RawTherapee with the env vars GTK needs to find
# Homebrew's Adwaita icon theme and RT's bundled resources.
#
# Usage:
#   ./run.sh                  # GUI, no args
#   ./run.sh path/to/img.x3f  # GUI, opens the file in the editor
#   ./run.sh --cli ...        # rawtherapee-cli, passing remaining args through

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BREW_PREFIX="${BREW_PREFIX:-/opt/homebrew}"

# RT's resources land here when built with OSX_DEV_BUILD=ON.
RT_RESOURCES="$REPO_DIR/build/Release/Resources/share"

# GTK looks in XDG_DATA_DIRS for icon themes, mime info, schemas, etc.
# Homebrew's Adwaita icon theme (fallback for 'image-missing' and friends)
# lives under /opt/homebrew/share, which isn't on the default search path.
export XDG_DATA_DIRS="${RT_RESOURCES}:${BREW_PREFIX}/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# Compiled gsettings schemas (needed by some GTK widgets).
export GSETTINGS_SCHEMA_DIR="${BREW_PREFIX}/share/glib-2.0/schemas"

# librsvg pixbuf loader (used to render RT's SVG icons).
export GDK_PIXBUF_MODULE_FILE="${BREW_PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

# Force RT's custom icon theme as the working theme; Adwaita stays as fallback
# via the inheritance chain declared in RT's index.theme.
export GTK_THEME="${GTK_THEME:-Adwaita}"

if [[ "${1:-}" == "--cli" ]]; then
    shift
    exec "$REPO_DIR/install/rawtherapee-cli" "$@"
fi

exec "$REPO_DIR/install/rawtherapee" "$@"
