#!/usr/bin/env bash
#
# Usage:
#   ./build.sh              # configure (if needed) + build
#   ./build.sh --run        # build + launch detached (no logs)
#   ./build.sh --dev        # build Debug + run with live logs in terminal
#   ./build.sh --clean      # wipe build dir AND app data (cookies, sessions,
#                           # profiles, caches, prefs/flags such as first-run
#                           # setup) for a true clean slate, then reconfigure
#   ./build.sh --clean --keep-data  # wipe build dir only, keep app data
#   ./build.sh --package    # Release build + distributable package in dist/
#                           # (macOS: deployed .app + .dmg, Linux: .tar.gz)
#   ./build.sh --yes        # install missing dependencies without prompting
#

set -euo pipefail

# ── detect OS ────────────────────────────────────────────────────────────────

IS_MAC=0
IS_LINUX=0
case "$(uname -s)" in
    Darwin*) IS_MAC=1   ;;
    Linux)   IS_LINUX=1 ;;
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
        qmake6 -query QT_INSTALL_PREFIX
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

    echo "$best"
}

# ── args ─────────────────────────────────────────────────────────────────────

DO_CLEAN=0
DO_KEEP_DATA=0
DO_RUN=0
DO_DEV=0
DO_PACKAGE=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --clean)     DO_CLEAN=1     ;;
        --keep-data) DO_KEEP_DATA=1 ;;
        --run)    DO_RUN=1     ;;
        --dev)    DO_DEV=1     ;;
        --package) DO_PACKAGE=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--clean [--keep-data]] [--run | --dev] [--package] [--yes]"
            exit 1
            ;;
    esac
done

if (( DO_PACKAGE )) && (( DO_DEV )); then
    echo "✗ --package builds Release; it can't be combined with --dev."
    exit 1
fi

if (( DO_KEEP_DATA )) && (( ! DO_CLEAN )); then
    echo "Note: --keep-data has no effect without --clean."
fi

clean_app_data() {
    (( DO_CLEAN )) || return 0
    (( DO_KEEP_DATA )) && { echo "→ Keeping app data (--keep-data)."; return 0; }
    echo "→ Removing app data (cookies, sessions, profiles, caches, prefs)…"
    if (( IS_MAC )); then
        if pgrep -f "QT_Illuminate.app/Contents/MacOS/QT_Illuminate" >/dev/null 2>&1; then
            echo "  Quitting other running copies…"
            pkill -KILL -f "QT_Illuminate.app/Contents/MacOS/QT_Illuminate" || true
        fi
        rm -rf \
            "$HOME/Library/Application Support/QT_Illuminate" \
            "$HOME/Library/Caches/QT_Illuminate" \
            "$HOME/Library/Application Support/logs/browser.log" \
            "$HOME/Library/Application Support/logs/browser.log.1"
        local plist domain
        for plist in "$HOME/Library/Preferences/"*[Ii]lluminate*.plist \
                     "$HOME/Library/Preferences/ByHost/"*[Ii]lluminate*.plist; do
            [[ -e "$plist" ]] || continue
            domain="$(basename "$plist" .plist)"
            echo "  Clearing prefs: $domain"
            if [[ "$plist" == */ByHost/* ]]; then
                defaults -currentHost delete "${domain%.*}" >/dev/null 2>&1 || true
            else
                defaults delete "$domain" >/dev/null 2>&1 || true
            fi
            rm -f "$plist"
        done
    else
        rm -rf \
            "${XDG_DATA_HOME:-$HOME/.local/share}/QT_Illuminate" \
            "${XDG_CACHE_HOME:-$HOME/.cache}/QT_Illuminate" \
            "${XDG_CONFIG_HOME:-$HOME/.config}/QT_Illuminate" \
            "${XDG_CONFIG_HOME:-$HOME/.config}/qt-illuminate.local"
    fi
}

# ── Dependencies ─────────────────────────────────────────────────────────────
confirm() {
    (( ASSUME_YES )) && return 0
    [[ -t 0 ]] || return 1
    local reply
    read -r -p "$1 [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

detect_pkg_mgr() {
    if (( IS_MAC )); then
        command -v brew >/dev/null 2>&1 && echo brew
        return 0
    fi
    local pm
    for pm in apt-get dnf pacman zypper; do
        if command -v "$pm" >/dev/null 2>&1; then
            echo "$pm"
            return 0
        fi
    done
}

# WebEngine ships separately from qtbase in most distributions
qt_has_webengine() {
    local prefix="$1" dir
    for dir in "$prefix"/lib/cmake "$prefix"/lib64/cmake "$prefix"/lib/*/cmake; do
        [[ -f "$dir/Qt6WebEngineQuick/Qt6WebEngineQuickConfig.cmake" ]] && return 0
    done
    return 1
}

has_compiler() {
    if (( IS_MAC )); then
        xcode-select -p >/dev/null 2>&1
    else
        command -v c++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 || command -v clang++ >/dev/null 2>&1
    fi
}

MISSING=()
QT_PREFIX=""
QT_NEEDS_WEBENGINE=0

check_deps() {
    MISSING=()
    QT_NEEDS_WEBENGINE=0
    has_compiler || MISSING+=("C++ compiler")
    command -v cmake >/dev/null 2>&1 || MISSING+=("cmake")
    if (( IS_LINUX )); then
        command -v ninja >/dev/null 2>&1 || MISSING+=("ninja")
    fi
    QT_PREFIX="$(find_qt)"
    if [[ -z "$QT_PREFIX" ]]; then
        MISSING+=("Qt 6")
    elif ! qt_has_webengine "$QT_PREFIX"; then
        QT_NEEDS_WEBENGINE=1
        MISSING+=("Qt WebEngine (Qt found at $QT_PREFIX)")
    fi
}

# drop apt packages this release doesn't carry, so one bad name doesn't sink
# the whole install
apt_available() {
    local p
    for p in "$@"; do
        apt-cache show "$p" >/dev/null 2>&1 && echo "$p"
    done
}

# true if any MISSING entry contains all of the given substrings
missing_has() {
    local item match s
    for item in "${MISSING[@]}"; do
        match=1
        for s in "$@"; do
            [[ "$item" == *"$s"* ]] || { match=0; break; }
        done
        (( match )) && return 0
    done
    return 1
}

install_command() {
    local pm="$1" pkgs=()
    case "$pm" in
        brew)
            missing_has cmake && pkgs+=("cmake")
            { missing_has "Qt 6" || missing_has "Qt WebEngine"; } && pkgs+=("qt")
            [[ ${#pkgs[@]} -gt 0 ]] && echo "brew install ${pkgs[*]}" || echo ""
            ;;
        apt-get)
            missing_has "C++ compiler" && pkgs+=("build-essential")
            missing_has cmake && pkgs+=("cmake")
            missing_has ninja && pkgs+=("ninja-build")
            if missing_has "Qt 6"; then
                pkgs+=(qt6-base-dev qt6-base-private-dev \
                    qt6-declarative-dev qt6-declarative-private-dev \
                    qt6-webengine-dev qt6-webengine-private-dev qt6-webengine-dev-tools \
                    qt6-webchannel-dev qt6-tools-dev \
                    qml6-module-qtquick qml6-module-qtquick-controls \
                    qml6-module-qtquick-dialogs qml6-module-qtquick-layouts \
                    qml6-module-qtquick-templates qml6-module-qtquick-window \
                    qml6-module-qtquick-effects qml6-module-qtqml-workerscript \
                    qml6-module-qtwebengine qml6-module-qtwebchannel)
            elif missing_has "Qt WebEngine"; then
                pkgs+=(qt6-webengine-dev qt6-webengine-private-dev qt6-webengine-dev-tools \
                    qt6-webchannel-dev \
                    qml6-module-qtwebengine qml6-module-qtwebchannel)
            fi
            # apt package names vary by release; filter out anything apt-cache
            # doesn't recognize instead of using it below and failing wholesale
            local pkgs_str
            pkgs_str="$(apt_available "${pkgs[@]}" | tr '\n' ' ')"
            echo "sudo apt-get install -y $pkgs_str"
            ;;
        dnf)
            missing_has "C++ compiler" && pkgs+=("gcc-c++")
            missing_has cmake && pkgs+=("cmake")
            missing_has ninja && pkgs+=("ninja-build")
            if missing_has "Qt 6"; then
                pkgs+=(qt6-qtbase-devel qt6-qtbase-private-devel \
                    qt6-qtdeclarative-devel qt6-qtwebengine-devel qt6-qtwebchannel-devel)
            elif missing_has "Qt WebEngine"; then
                pkgs+=(qt6-qtwebengine-devel qt6-qtwebchannel-devel)
            fi
            [[ ${#pkgs[@]} -gt 0 ]] && echo "sudo dnf install -y ${pkgs[*]}" || echo ""
            ;;
        pacman)
            missing_has "C++ compiler" && pkgs+=("base-devel")
            missing_has cmake && pkgs+=("cmake")
            missing_has ninja && pkgs+=("ninja")
            if missing_has "Qt 6"; then
                pkgs+=(qt6-base qt6-declarative qt6-webengine qt6-webchannel)
            elif missing_has "Qt WebEngine"; then
                pkgs+=(qt6-webengine qt6-webchannel)
            fi
            [[ ${#pkgs[@]} -gt 0 ]] && echo "sudo pacman -S --needed --noconfirm ${pkgs[*]}" || echo ""
            ;;
        zypper)
            missing_has "C++ compiler" && pkgs+=("gcc-c++")
            missing_has cmake && pkgs+=("cmake")
            missing_has ninja && pkgs+=("ninja")
            if missing_has "Qt 6"; then
                pkgs+=(qt6-base-devel qt6-base-private-devel qt6-declarative-devel \
                    qt6-webengine-devel qt6-webchannel-devel)
            elif missing_has "Qt WebEngine"; then
                pkgs+=(qt6-webengine-devel qt6-webchannel-devel)
            fi
            [[ ${#pkgs[@]} -gt 0 ]] && echo "sudo zypper install -y ${pkgs[*]}" || echo ""
            ;;
    esac
}

install_homebrew() {
    echo "→ Installing Homebrew…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$brew_bin" ]]; then
            eval "$("$brew_bin" shellenv)"
            return 0
        fi
    done
    echo "✗ Homebrew install finished but brew was not found."
    exit 1
}

install_deps() {
    if (( IS_MAC )) && ! has_compiler; then
        echo "→ Opening the Xcode Command Line Tools installer…"
        xcode-select --install || true
        echo "  Finish that install, then run $0 again."
        exit 1
    fi

    local pm
    pm="$(detect_pkg_mgr)"
    if [[ -z "$pm" ]] && (( IS_MAC )); then
        if confirm "Homebrew is needed to install the rest. Install Homebrew?"; then
            install_homebrew
            pm=brew
        else
            echo "✗ Install Homebrew (https://brew.sh) or Qt (https://www.qt.io/download-qt-installer) and try again."
            exit 1
        fi
    fi
    if [[ -z "$pm" ]]; then
        echo "✗ No supported package manager found. Install cmake, ninja and Qt 6 (with WebEngine) manually."
        exit 1
    fi

    [[ "$pm" == "apt-get" ]] && sudo apt-get update
    local cmd
    cmd="$(install_command "$pm")"
    if [[ -z "${cmd// }" ]]; then
        echo "✗ Nothing translatable to a package-manager command is missing."
        exit 1
    fi
    echo "→ Running: $cmd"
    eval "$cmd"
}

check_deps
if (( ${#MISSING[@]} )); then
    echo "✗ Missing build dependencies:"
    printf '    • %s\n' "${MISSING[@]}"
    if confirm "Install them now?"; then
        install_deps
        hash -r
        check_deps
    else
        pm="$(detect_pkg_mgr)"
        if [[ -n "$pm" ]]; then
            echo "  To install manually: $(install_command "$pm")"
        fi
        (( ASSUME_YES )) || [[ -t 0 ]] || echo "  Re-run with --yes to install without prompting."
        exit 1
    fi

    if (( QT_NEEDS_WEBENGINE )) && (( ${#MISSING[@]} == 1 )); then
        echo "⚠ Couldn't confirm Qt WebEngine under $QT_PREFIX; continuing anyway."
    elif (( ${#MISSING[@]} )); then
        echo "✗ Still missing after install:"
        printf '    • %s\n' "${MISSING[@]}"
        exit 1
    else
        echo "✓ Dependencies installed."
    fi
fi

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

# qt location (resolved by check_deps)
echo "→ Using Qt at: $QT_PREFIX"

# ── Configure ────────────────────────────────────────────────────────────────
CONFIGURED_TYPE=""
if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    CONFIGURED_TYPE="$(sed -n 's/^CMAKE_BUILD_TYPE:[A-Z]*=//p' "$BUILD_DIR/CMakeCache.txt")"
fi

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]] || [[ "$CONFIGURED_TYPE" != "$BUILD_TYPE" ]]; then
    echo "→ Configuring ($BUILD_TYPE)…"
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

# quit above re-saves session on the way out, so wipe app data after it
clean_app_data

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

# ── package ──────────────────────────────────────────────────────────────────

if (( DO_PACKAGE )); then
    APP_VERSION="$(sed -n 's/^project(QT_Illuminate VERSION \([0-9.]*\).*/\1/p' "$SCRIPT_DIR/CMakeLists.txt")"
    DIST_DIR="$SCRIPT_DIR/dist"
    STAGE_DIR="$DIST_DIR/stage"
    rm -rf "$STAGE_DIR"
    mkdir -p "$DIST_DIR"

    if (( IS_MAC )); then
        echo "→ Deploying Qt into the app bundle…"
        MACDEPLOYQT="$QT_PREFIX/bin/macdeployqt"
        [[ -x "$MACDEPLOYQT" ]] || MACDEPLOYQT="$(command -v macdeployqt || true)"
        [[ -n "$MACDEPLOYQT" ]] || { echo "✗ macdeployqt not found under $QT_PREFIX/bin"; exit 1; }
        QT_QML_DIR="$("$QT_PREFIX/bin/qtpaths6" --query QT_INSTALL_QML 2>/dev/null \
                      || "$QT_PREFIX/bin/qmake" -query QT_INSTALL_QML)"

        QML_IMPORTS="$BUILD_DIR/deploy-qml"
        rm -rf "$QML_IMPORTS"
        cp -RL "$QT_QML_DIR" "$QML_IMPORTS"

        STAGED_APP="$STAGE_DIR/QT_Illuminate.app"
        mkdir -p "$STAGE_DIR"
        cp -R "$APP_BUNDLE" "$STAGED_APP"
        "$MACDEPLOYQT" "$STAGED_APP" -qmldir="$SCRIPT_DIR/ui" -qmlimport="$QML_IMPORTS"
        rm -rf "$QML_IMPORTS"

        BROKEN_LINKS="$(find "$STAGED_APP" -type l ! -exec test -e {} \; -print)"
        if [[ -n "$BROKEN_LINKS" ]]; then
            echo "✗ Deployed bundle has dangling symlinks:"
            echo "$BROKEN_LINKS" | head -10
            exit 1
        fi
        [[ -d "$STAGED_APP/Contents/Frameworks/QtWebEngineCore.framework" ]] || {
            echo "✗ Deployed bundle is missing QtWebEngineCore.framework"
            exit 1
        }

        # deployment rewrites install names, which invalidates signatures;
        # re-sign (ad-hoc unless CODESIGN_IDENTITY names a real identity)
        echo "→ Signing (${CODESIGN_IDENTITY:-ad-hoc})…"
        codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$STAGED_APP"

        DMG_PATH="$DIST_DIR/QT_Illuminate-${APP_VERSION}-macos-$(uname -m).dmg"
        echo "→ Creating disk image…"
        ln -s /Applications "$STAGE_DIR/Applications"
        rm -f "$DMG_PATH"
        hdiutil create -volname "QT_Illuminate" -srcfolder "$STAGE_DIR" \
                -ov -format UDZO "$DMG_PATH" >/dev/null
        rm -rf "$DIST_DIR/QT_Illuminate.app"
        mv "$STAGED_APP" "$DIST_DIR/"
        rm -rf "$STAGE_DIR"
        echo "✓ Package: $DMG_PATH"
        echo "  App:     $DIST_DIR/QT_Illuminate.app"
    else
        # FHS tree (bin/, share/applications, share/icons) against system Qt
        echo "→ Installing into staging tree…"
        cmake --install "$BUILD_DIR" --config "$BUILD_TYPE" --prefix "$STAGE_DIR/usr"
        TAR_PATH="$DIST_DIR/QT_Illuminate-${APP_VERSION}-linux-$(uname -m).tar.gz"
        tar -C "$STAGE_DIR" -czf "$TAR_PATH" usr
        rm -rf "$STAGE_DIR"
        echo "✓ Package: $TAR_PATH"
        echo "  Extract to / (or a prefix) — requires the distro's Qt 6 WebEngine packages."
    fi
fi

# ── run (detached) ───────────────────────────────────────────────────────────

if (( DO_RUN )) && (( ! DO_DEV )); then
    echo "→ Launching ${APP_LABEL} (detached)…"
    export QTWEBENGINE_DISABLE_SANDBOX=1
    if (( IS_MAC )); then
        # open goes through launchd, which doesn't inherit our environment
        open --env QTWEBENGINE_DISABLE_SANDBOX=1 "$APP_BUNDLE"
    else
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

    # dev builds are unsigned; see the detached-run block above
    export QTWEBENGINE_DISABLE_SANDBOX=1
    "$APP_BINARY" 2>&1 | tee -a "$LOG_FILE" &
    APP_PID=$!
    trap 'kill "$APP_PID" 2>/dev/null; exit 0' INT TERM
    wait "$APP_PID"
fi