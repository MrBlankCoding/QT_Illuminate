#!/usr/bin/env zsh
#
# Usage:
#   ./build.sh              # configure (if needed) + build
#   ./build.sh --run        # build + launch via open (detached, no logs)
#   ./build.sh --dev        # build Debug + run with live logs in terminal
#   ./build.sh --clean      # wipe build dir and reconfigure
#

set -euo pipefail

# ── Locate Qt ────────────────────────────────────────────────────────────────

find_qt() {
    if [[ -n "${QT_DIR:-}" ]]; then
        echo "$QT_DIR"
        return
    fi

    if command -v qmake6 &>/dev/null; then
        echo "$(qmake6 -query QT_INSTALL_PREFIX)"
        return
    fi
    if command -v qmake &>/dev/null; then
        local prefix
        prefix="$(qmake -query QT_INSTALL_PREFIX 2>/dev/null || true)"
        if [[ "$prefix" == *Qt* || "$prefix" == *qt* ]]; then
            echo "$prefix"
            return
        fi
    fi

    # QT installer locations
    local search_roots=(
        "$HOME/Qt"
        "/opt/Qt"
        "/usr/local/Qt"
        "/Applications/Qt"
    )
    local best=""
    for root in "${search_roots[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r candidate; do
            [[ -f "$candidate/lib/cmake/Qt6/Qt6Config.cmake" ]] || continue
            if [[ -z "$best" || "$candidate" > "$best" ]]; then
                best="$candidate"
            fi
        done < <(find "$root" -maxdepth 2 -type d -name "macos" 2>/dev/null | grep "/6\." | sort)
    done

    if [[ -n "$best" ]]; then
        echo "$best"
        return
    fi

    echo ""
}

# args

DO_CLEAN=0
DO_RUN=0
DO_DEV=0
for arg in "$@"; do
    case "$arg" in
        --clean) DO_CLEAN=1 ;;
        --run)   DO_RUN=1   ;;
        --dev)   DO_DEV=1   ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--clean] [--run | --dev]"
            exit 1
            ;;
    esac
done

# --dev implies a Debug build; plain --run keeps Release.
BUILD_TYPE="Release"
(( DO_DEV )) && BUILD_TYPE="Debug"


SCRIPT_DIR="${0:A:h}"          
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/QT_Illuminate.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/QT_Illuminate"

if (( DO_CLEAN )) && [[ -d "$BUILD_DIR" ]]; then
    echo "→ Removing build directory…"
    rm -rf "$BUILD_DIR"
fi

# qt location

QT_PREFIX="$(find_qt)"
if [[ -z "$QT_PREFIX" ]]; then
    echo "✗ Could not locate a Qt 6 installation."
    echo "  Set QT_DIR to your Qt macos kit, e.g.:"
    echo "    QT_DIR=~/Qt/6.7.0/macos ./build.sh"
    exit 1
fi
echo "→ Using Qt at: $QT_PREFIX"

# ── Configure ────────────────────────────────────────────────────────────────

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "→ Configuring…"
    cmake -S "$SCRIPT_DIR" \
          -B "$BUILD_DIR"  \
          -DCMAKE_PREFIX_PATH="$QT_PREFIX" \
          -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
fi

# remove previous build
#
# Full re-deploy of QtWebEngine (via macdeployqt) only needs to happen once
# per bundle: on a --clean build, or the very first build. Otherwise we keep
# the existing Frameworks in place and just let cmake overwrite the binary,
# so day-to-day (warm) builds are fast.
NEEDS_FULL_DEPLOY=0
if (( DO_CLEAN )) || [[ ! -d "$APP_BUNDLE/Contents/Frameworks" ]]; then
    NEEDS_FULL_DEPLOY=1
    rm -rf "$APP_BUNDLE"
fi

echo "→ Building…"
cmake --build "$BUILD_DIR" --config "$BUILD_TYPE" --parallel "$(sysctl -n hw.logicalcpu)"

# QT frameworks

if (( NEEDS_FULL_DEPLOY )); then
    MACDEPLOYQT="${QT_PREFIX}/bin/macdeployqt"
    if [[ ! -x "$MACDEPLOYQT" ]]; then
        MACDEPLOYQT="$(command -v macdeployqt || true)"
    fi

    if [[ -n "${MACDEPLOYQT:-}" ]] && [[ -d "$APP_BUNDLE" ]]; then
        echo "→ Deploying Qt frameworks (full re-deploy of QtWebEngine takes a minute or two)…"
        "$MACDEPLOYQT" "$APP_BUNDLE" -qmldir="$SCRIPT_DIR/ui" \
            && echo "  Qt deployment OK." \
            || echo "  ⚠ macdeployqt reported errors; bundle may be incomplete."
    fi
else
    echo "→ Skipping macdeployqt (warm build, Qt frameworks already in bundle)."
fi

if [[ -f "$APP_BINARY" ]]; then
    install_name_tool -delete_rpath /opt/homebrew/lib "$APP_BINARY" 2>/dev/null || true
    if ! otool -l "$APP_BINARY" 2>/dev/null | grep -A1 "LC_RPATH" | grep -q "@executable_path/../Frameworks"; then
        install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BINARY" 2>/dev/null || true
    fi
    if (( NEEDS_FULL_DEPLOY )); then
        # Full bundle just landed via macdeployqt: fix every Mach-O
        # (frameworks, plugins, helper apps, and the main executable) and
        # deep-sign the whole tree.
        python3 "$SCRIPT_DIR/deploy-fixup.py" "$APP_BUNDLE" "$APP_BINARY" || \
            echo "  ⚠ deploy-fixup.py failed; bundle may still reference Homebrew Qt."
        # Deep-sign the entire tree, then verify. macdeployqt leaves Homebrew
        # dylibs with stale signatures and --deep can bail on stragglers, so
        # re-run once if verification fails.
        codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
        if ! codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
            codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
        fi
    else
        # Warm build: only the main executable was relinked. The
        # Frameworks/PlugIns tree is untouched since the last full deploy, so
        # just fix + resign the executable instead of re-walking and
        # deep-signing ~2000 Mach-O files on every build.
        python3 "$SCRIPT_DIR/deploy-fixup.py" "$APP_BUNDLE" "$APP_BINARY" --main-only || \
            echo "  ⚠ deploy-fixup.py failed; binary may still reference Homebrew Qt."
        codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
        # If a stale signature survived in Frameworks/PlugIns (e.g. from an
        # earlier partial deploy), heal the whole tree now.
        if ! codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
            echo "  → Healing stale signatures in Frameworks/PlugIns…"
            codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
        fi
    fi
    if codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
        echo "  ✓ Bundle signature verified."
    else
        echo "  ⚠ Bundle signature does not fully verify:"
        codesign --verify --deep --strict "$APP_BUNDLE" 2>&1 || true
    fi
fi

echo "✓ Build succeeded."
echo "  App bundle: $APP_BUNDLE"

# run

if (( DO_RUN )); then
    if [[ -f "$APP_BINARY" ]]; then
        echo "→ Launching QT_Illuminate.app (detached)…"
        open "$APP_BUNDLE"
    else
        echo "✗ Binary not found at expected path: $APP_BINARY"
        exit 1
    fi
fi

#  logs

if (( DO_DEV )); then
    if [[ ! -f "$APP_BINARY" ]]; then
        echo "✗ Binary not found at expected path: $APP_BINARY"
        exit 1
    fi

    LOG_FILE="$HOME/Library/Application Support/logs/browser.log"
    mkdir -p "$(dirname "$LOG_FILE")"

    echo "  Log file: $LOG_FILE"

    trap 'kill "$APP_PID" 2>/dev/null; exit 0' INT TERM

    "$APP_BINARY" 2>&1 | tee -a "$LOG_FILE" &
    APP_PID=$!
    wait "$APP_PID"
fi