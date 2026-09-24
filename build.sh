#!/usr/bin/env bash
#
#
# Usage:
#   ./build.sh              # configure (if needed) + build
#   ./build.sh --run        # build + launch detached (no logs)
#   ./build.sh --dev        # build Debug + run with live logs in terminal
#   ./build.sh --clean      # wipe build dir and reconfigure
#
#

set -euo pipefail

# detect OS

IS_MAC=0
IS_LINUX=0
case "$(uname -s)" in
    Darwin*) IS_MAC=1    ;;
    Linux)   IS_LINUX=1  ;;
    *)
        echo "✗ Unsupported platform: $(uname -s)"
        exit 1
        ;;
esac

cpu_cores() {
    if (( IS_MAC )); then
        sysctl -n hw.logicalcpu
    else
        nproc
    fi
}

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
        if [[ -n "$prefix" ]] && {
            [[ "$prefix" == *Qt* || "$prefix" == *qt* ]] || \
            [[ -f "$prefix/lib/cmake/Qt6/Qt6Config.cmake" ]]
        }; then
            echo "$prefix"
            return
        fi
    fi

    local best=""
    local candidate
    if (( IS_MAC )); then
        local search_roots=(
            "$HOME/Qt"
            "/opt/Qt"
            "/usr/local/Qt"
            "/Applications/Qt"
        )
        for root in "${search_roots[@]}"; do
            [[ -d "$root" ]] || continue
            while IFS= read -r candidate; do
                [[ -f "$candidate/lib/cmake/Qt6/Qt6Config.cmake" ]] || continue
                if [[ -z "$best" || "$candidate" > "$best" ]]; then
                    best="$candidate"
                fi
            done < <(find "$root" -maxdepth 2 -type d -name "macos" 2>/dev/null | grep "/6\." | sort)
        done
    else
        while IFS= read -r candidate; do
            [[ -f "$candidate/lib/cmake/Qt6/Qt6Config.cmake" ]] || continue
            if [[ -z "$best" || "$candidate" > "$best" ]]; then
                best="$candidate"
            fi
        done < <(find /usr /usr/local /opt -maxdepth 7 -type f \
                    -name Qt6Config.cmake -path "*/lib/cmake/Qt6/*" 2>/dev/null \
                    | sed -E 's#/lib(64)?/([^/]*/)?cmake/Qt6/Qt6Config\.cmake$##' \
                    | sort -u)
    fi

    if [[ -n "$best" ]]; then
        echo "$best"
        return
    fi

    echo ""
}

# ── Required tools ───────────────────────────────────────────────────────────

command -v cmake >/dev/null 2>&1 || {
    echo "✗ cmake not found."
    exit 1
}
if (( IS_LINUX )); then
    command -v ninja >/dev/null 2>&1 || {
        echo "✗ ninja not found."
        exit 1
    }
fi

# ── args ─────────────────────────────────────────────────────────────────────

DO_CLEAN=0
DO_RUN=0
DO_DEV=0
for arg in "$@"; do
    case "$arg" in
        --clean)   DO_CLEAN=1   ;;
        --run)     DO_RUN=1     ;;
        --dev)     DO_DEV=1     ;;
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

APP_LABEL="QT_Illuminate"
if (( IS_MAC )); then
    APP_BUNDLE="$BUILD_DIR/QT_Illuminate.app"
    APP_BINARY="$APP_BUNDLE/Contents/MacOS/QT_Illuminate"
    APP_LABEL="QT_Illuminate.app"
else
    APP_BUNDLE=""
    APP_BINARY="$BUILD_DIR/QT_Illuminate"
fi

if (( DO_CLEAN )) && [[ -d "$BUILD_DIR" ]]; then
    echo "→ Removing build directory…"
    rm -rf "$BUILD_DIR"
fi

# qt location

QT_PREFIX="$(find_qt)"
if [[ -z "$QT_PREFIX" ]]; then
    echo "✗ Could not locate a Qt 6 installation."
    exit 1
fi
echo "→ Using Qt at: $QT_PREFIX"

# ── Configure ────────────────────────────────────────────────────────────────

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "→ Configuring…"
    if (( IS_LINUX )); then
        cmake -S "$SCRIPT_DIR" \
              -B "$BUILD_DIR"  \
              -G Ninja \
              -DCMAKE_PREFIX_PATH="$QT_PREFIX" \
              -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    else
        cmake -S "$SCRIPT_DIR" \
              -B "$BUILD_DIR"  \
              -DCMAKE_PREFIX_PATH="$QT_PREFIX" \
              -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    fi
fi

if pgrep -f "$APP_BINARY" >/dev/null 2>&1; then
    echo "→ Quitting running ${APP_LABEL}…"
    if (( IS_MAC )); then
        # a normal quit, so the session is saved on the way out
        osascript -e 'quit app id "local.qt-illuminate.QT_Illuminate"' >/dev/null 2>&1 || true
    else
        pkill -TERM -f "$APP_BINARY" || true
    fi
    for _ in $(seq 1 50); do
        pgrep -f "$APP_BINARY" >/dev/null 2>&1 || break
        sleep 0.1
    done
    if pgrep -f "$APP_BINARY" >/dev/null 2>&1; then
        echo "  Still running after 5s; killing it."
        pkill -KILL -f "$APP_BINARY" || true
    fi
fi

# remove previous build
rm -rf "$APP_BUNDLE" 2>/dev/null || true

echo "→ Building…"
cmake --build "$BUILD_DIR" --config "$BUILD_TYPE" --parallel "$(cpu_cores)"

if (( IS_MAC )); then
    if [[ -d "$APP_BUNDLE/Contents/Frameworks" ]] || [[ -d "$APP_BUNDLE/Contents/PlugIns" ]]; then
        echo "→ Removing previously deployed Qt frameworks (dev bundle runs against dev Qt)…"
        rm -rf "$APP_BUNDLE"
        cmake --build "$BUILD_DIR" --target QT_Illuminate --config "$BUILD_TYPE" \
              --parallel "$(cpu_cores)"
    fi
fi

if [[ -f "$APP_BINARY" ]]; then
    echo "✓ Build succeeded."
    if (( IS_MAC )); then
        echo "  App bundle: $APP_BUNDLE"
    else
        echo "  Binary: $APP_BINARY"
    fi
else
    echo "✗ Build finished but binary not found at expected path: $APP_BINARY"
    exit 1
fi

# ── run (detached) ───────────────────────────────────────────────────────────

if (( DO_RUN )) && ! (( DO_DEV )); then
    if (( IS_MAC )); then
        echo "→ Launching ${APP_LABEL} (detached)…"
        open "$APP_BUNDLE"
    else
        echo "→ Launching ${APP_LABEL} (detached)…"
        nohup "$APP_BINARY" >/dev/null 2>&1 &
        disown
        echo "  PID: $!"
    fi
fi

# ── dev (foreground, live logs) ──────────────────────────────────────────────

if (( DO_DEV )); then
    if [[ ! -f "$APP_BINARY" ]]; then
        echo "✗ Binary not found at expected path: $APP_BINARY"
        exit 1
    fi

    if (( IS_MAC )); then
        LOG_DIR="$HOME/Library/Application Support/logs"
    else
        LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/QT_Illuminate/QT_Illuminate/logs"
    fi
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/browser.log"

    echo "  Log file: $LOG_FILE"

    trap 'kill "$APP_PID" 2>/dev/null; exit 0' INT TERM

    "$APP_BINARY" 2>&1 | tee -a "$LOG_FILE" &
    APP_PID=$!
    wait "$APP_PID"
fi