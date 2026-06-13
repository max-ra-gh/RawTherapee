#!/usr/bin/env bash
# Install/uninstall RawTherapee macOS build dependencies.
#
# The 'install' command snapshots your currently-installed brew formulae to a
# state file BEFORE installing anything new. The 'uninstall' command diffs that
# snapshot against the current state and removes only the formulae that were
# added since — your pre-existing tools are never touched.
#
# Usage:
#   ./brew-install.sh install     # snapshot + install everything below
#   ./brew-install.sh uninstall   # remove only what was added since the snapshot
#   ./brew-install.sh list        # print the dependency list
#   ./brew-install.sh diff        # show what would be removed by 'uninstall'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.brew-pre-install-state.txt"

# Mirrors .github/workflows/macos.yml armbuild job.
DEPS=(
    cmake
    ninja
    pkg-config
    gtk+3
    gtkmm3
    gtk-mac-integration
    adwaita-icon-theme
    libsigc++@2
    little-cms2
    libiptcdata
    fftw
    lensfun
    expat
    shared-mime-info
    exiv2
    jpeg-xl
    libomp
    automake
    libtool
    simde
    libtiff
    # llvm, imagemagick, create-dmg trimmed:
    #   - llvm (~1.5 GB): CI installs it, but the build uses system Xcode clang/clang++
    #     and openmp comes from the separate libomp package.
    #   - imagemagick + create-dmg: only needed for `make macosx_bundle` (.app/.dmg
    #     packaging). Plain `make install` runs RT fine without them.
)

snapshot_now() {
    brew list --formula | sort -u
}

added_since_snapshot() {
    comm -13 <(sort -u "$STATE_FILE") <(snapshot_now)
}

cmd="${1:-help}"

case "$cmd" in
    install)
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "Snapshotting currently-installed brew formulae -> $STATE_FILE"
            snapshot_now > "$STATE_FILE"
            echo "  ($(wc -l < "$STATE_FILE" | tr -d ' ') formulae already installed)"
        else
            echo "Snapshot exists at $STATE_FILE; reusing it."
        fi
        echo "Installing ${#DEPS[@]} dependencies (transitive deps will be pulled too)..."
        brew install "${DEPS[@]}"
        echo
        echo "Done. To remove only what was added, run: $0 uninstall"
        ;;

    diff)
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "No snapshot at $STATE_FILE — run '$0 install' first."
            exit 1
        fi
        added="$(added_since_snapshot)"
        if [[ -z "$added" ]]; then
            echo "No new formulae since the snapshot."
            exit 0
        fi
        count="$(printf '%s\n' "$added" | wc -l | tr -d ' ')"
        echo "$count formula(e) added since snapshot:"
        printf '  %s\n' $added
        ;;

    uninstall)
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "No snapshot at $STATE_FILE — cannot tell what was added."
            echo "Refusing to proceed (would risk removing pre-existing packages)."
            exit 1
        fi
        added="$(added_since_snapshot)"
        if [[ -z "$added" ]]; then
            echo "No new formulae since snapshot. Nothing to do."
            rm -f "$STATE_FILE"
            exit 0
        fi
        count="$(printf '%s\n' "$added" | wc -l | tr -d ' ')"
        echo "Will uninstall up to $count formula(e) added since the snapshot:"
        printf '  %s\n' $added
        printf 'Proceed? [y/N] '
        read -r ans
        ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
        if [[ "$ans" != "y" && "$ans" != "yes" ]]; then
            echo "Aborted."
            exit 1
        fi

        # Walk the dependency graph: only uninstall current leaves (no installed
        # package depends on them) — looping picks up newly-exposed leaves as
        # earlier ones are removed. Safer than --ignore-dependencies.
        for pass in 1 2 3 4 5; do
            remaining="$(added_since_snapshot)"
            [[ -z "$remaining" ]] && break
            leaves="$(brew leaves)"
            to_remove="$(comm -12 \
                <(printf '%s\n' "$remaining" | sort -u) \
                <(printf '%s\n' "$leaves" | sort -u))"
            [[ -z "$to_remove" ]] && break
            echo "Pass $pass — uninstalling leaves:"
            printf '  %s\n' $to_remove
            # shellcheck disable=SC2086
            brew uninstall $to_remove
        done

        # Sweep orphaned transitive deps that brew flagged as "installed as dependency".
        echo "Running brew autoremove..."
        brew autoremove || true

        # Anything left in the diff is something the user (or another tool)
        # explicitly requested separately — leave it alone, just report it.
        leftover="$(added_since_snapshot)"
        if [[ -n "$leftover" ]]; then
            echo
            echo "These formulae are still installed and were marked installed-on-request"
            echo "elsewhere; not removing automatically:"
            printf '  %s\n' $leftover
            echo "Remove manually with: brew uninstall <name>"
        fi
        rm -f "$STATE_FILE"
        echo "Done."
        ;;

    list)
        printf '%s\n' "${DEPS[@]}"
        ;;

    help|-h|--help)
        sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
        ;;

    *)
        echo "Unknown command: $cmd"
        echo "Usage: $0 {install|uninstall|diff|list|help}"
        exit 1
        ;;
esac
