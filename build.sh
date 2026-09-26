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
#

set -euo pipefail

# ── snapshot self, then re-exec the copy ─────────────────────────────────────
# Bash reads a script incrementally by byte offset, so saving this file while
# it runs (a 115MB DMG step gives plenty of time) makes bash resume at a stale
# offset and die on a bogus syntax error in an unrelated line. Re-execing a
# byte-identical snapshot makes mid-run edits harmless; line numbers still match
# because the copy is byte-for-byte. The real project dir travels in
# QT_ILLUMINATE_ROOT, since BASH_SOURCE[0] would otherwise point at the temp
# file and send SCRIPT_DIR to /tmp.
if [[ -z "${QT_ILLUMINATE_ROOT:-}" ]]; then
    _qt_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    _qt_snap="$(mktemp "${TMPDIR:-/tmp}/qt_illuminate_build.XXXXXX")"
    cat -- "${BASH_SOURCE[0]}" > "$_qt_snap"
    chmod +x "$_qt_snap"
    export QT_ILLUMINATE_ROOT="$_qt_root"
    export QT_ILLUMINATE_SNAPSHOT="$_qt_snap"
    exec bash "$_qt_snap" "$@"
fi
trap 'rm -f "${QT_ILLUMINATE_SNAPSHOT:-/dev/null}"' EXIT

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
version_ge() {
    local v1 v2
    v1="$(grep -oE '[0-9]+(\.[0-9]+)+' <<<"$1" | head -1)"
    v2="$(grep -oE '[0-9]+(\.[0-9]+)+' <<<"$2" | head -1)"
    [[ -z "$v2" ]] && return 0
    [[ -z "$v1" ]] && return 1
    local IFS=.
    local -a a=($v1) b=($v2)
    local i n ai bi
    n=$(( ${#a[@]} > ${#b[@]} ? ${#a[@]} : ${#b[@]} ))
    for (( i = 0; i < n; i++ )); do
        ai="${a[i]:-0}"; bi="${b[i]:-0}"
        (( ai > bi )) && return 0
        (( ai < bi )) && return 1
    done
    return 0
}

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
                if [[ -z "$best" ]] || version_ge "$candidate" "$best"; then
                    best="$candidate"
                fi
            done < <(find "$root" -maxdepth 2 -type d -name "macos" 2>/dev/null | grep "/6\.")
        done
    else
        while IFS= read -r candidate; do
            [[ -f "$candidate/lib/cmake/Qt6/Qt6Config.cmake" ]] || continue
            if [[ -z "$best" ]] || version_ge "$candidate" "$best"; then
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
for arg in "$@"; do
    case "$arg" in
        --clean)     DO_CLEAN=1     ;;
        --keep-data) DO_KEEP_DATA=1 ;;
        --run)    DO_RUN=1     ;;
        --dev)    DO_DEV=1     ;;
        --package) DO_PACKAGE=1 ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: ./build.sh [--clean [--keep-data]] [--run | --dev] [--package]"
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

if (( DO_RUN )) && (( DO_DEV )); then
    echo "Note: --dev already runs the app in the foreground with live logs; ignoring --run."
    DO_RUN=0
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
qt_has_webengine() {
    local prefix="$1" dir
    for dir in "$prefix"/lib/cmake "$prefix"/lib64/cmake "$prefix"/lib/*/cmake; do
        [[ -f "$dir/Qt6WebEngineQuick/Qt6WebEngineQuickConfig.cmake" ]] && return 0
    done
    return 1
}

bundle_rpaths() {
    otool -l "$1" 2>/dev/null | awk '
        /LC_RPATH/ { f = 1 }
        f && /path / { sub(/^.*path /, ""); sub(/ \(offset.*/, ""); print; f = 0 }'
}

rpath_reaches_frameworks() {
    local bin="$1" fw="$2" rp dir
    while IFS= read -r rp; do
        case "$rp" in
            @loader_path/*) dir="$(dirname "$bin")/${rp#@loader_path/}" ;;
            /*)              dir="$rp" ;;
            *)              continue ;;
        esac
        dir="$(cd "$dir" 2>/dev/null && pwd -P)" || continue
        [[ "$dir" == "$fw" ]] && return 0
    done < <(bundle_rpaths "$bin")
    return 1
}

relink_bundle_deps() {
    local mode="fix"
    if [[ "${1:-}" == "--check" ]]; then
        mode="check"
        shift
    fi
    local app="$1"
    local fw_dir="$app/Contents/Frameworks"
    [[ -d "$fw_dir" ]] || return 0
    fw_dir="$(cd "$fw_dir" && pwd -P)"

    local bin dep id head rest new rel_dir rpath ups err short
    local -a args=()
    local relinked=0 dropped=0 unresolved=0
    while IFS= read -r -d '' bin; do
        file -b "$bin" 2>/dev/null | grep -q "Mach-O" || continue
        short="${bin#"$app"/}"

        args=()
        id="$(otool -D "$bin" 2>/dev/null | sed -n '2p')"
        [[ "$id" == /* ]] && args+=(-id "@rpath/${id##*/}")

        while IFS= read -r rpath; do
            [[ "$rpath" == /* ]] || continue
            if [[ "$mode" == "check" ]]; then
                printf '  %s → build-host rpath %s\n' "$short" "$rpath"
                unresolved=$((unresolved + 1))
                continue
            fi
            install_name_tool -delete_rpath "$rpath" "$bin" >/dev/null 2>&1 || true
            dropped=$((dropped + 1))
        done < <(bundle_rpaths "$bin")

        local uses_rpath=0
        while IFS= read -r dep; do
            if [[ "$mode" == "check" ]]; then
                # a dylib's first install name is its own id, not a load
                [[ "$dep" == "$id" ]] && continue
                case "$dep" in
                    @rpath/*) uses_rpath=1 ;;
                    /System/*|/usr/lib/*) continue ;;
                    @executable_path/*|/*)
                        printf '  %s → %s\n' "$short" "$dep"
                        unresolved=$((unresolved + 1)) ;;
                esac
                continue
            fi
            case "$dep" in
                @rpath/*) uses_rpath=1; continue ;;
                @executable_path/../Frameworks/*)
                    rest="${dep#@executable_path/../Frameworks/}"
                    ;;
                /*)
                    rest="${dep#/}"
                    while [[ "$rest" == */* ]]; do
                        head="${rest%%/*}"
                        [[ -e "$fw_dir/$head" ]] && break
                        rest="${rest#*/}"
                    done
                    ;;
                *)
                    continue
                    ;;
            esac
            [[ -e "$fw_dir/${rest%%/*}" ]] || continue
            new="@rpath/$rest"
            uses_rpath=1
            [[ "$new" == "$dep" ]] && continue
            args+=(-change "$dep" "$new")
        done < <(otool -L "$bin" 2>/dev/null | tail -n +2 | awk 'NF { print $1 }')

        if (( uses_rpath )) && ! rpath_reaches_frameworks "$bin" "$fw_dir"; then
            if [[ "$mode" == "check" ]]; then
                printf '  %s → @rpath deps with no rpath reaching Contents/Frameworks\n' "$short"
                unresolved=$((unresolved + 1))
                continue
            fi
            rel_dir="${bin#"$app"/}"; rel_dir="${rel_dir%/*}"; rel_dir="${rel_dir#*/}"
            ups=""
            while [[ -n "$rel_dir" ]]; do
                ups="../$ups"
                [[ "$rel_dir" == */* ]] && rel_dir="${rel_dir#*/}" || rel_dir=""
            done
            rpath="@loader_path/${ups}Frameworks"
            err="$(install_name_tool -add_rpath "$rpath" "$bin" 2>&1 >/dev/null)" || {
                echo "✗ Failed to add rpath $rpath to $short:"
                echo "$err"
                return 1
            }
            rpath_reaches_frameworks "$bin" "$fw_dir" || {
                echo "✗ $short still cannot resolve $rpath to the bundle's Frameworks."
                return 1
            }
        fi

        [[ "$mode" == "check" ]] && continue

        if [[ ${#args[@]} -gt 0 ]]; then
            err="$(install_name_tool "${args[@]}" "$bin" 2>&1 >/dev/null)" || {
                echo "✗ Failed to re-point dependencies in $short:"
                echo "$err"
                return 1
            }
            relinked=$((relinked + 1))
        fi
    done < <(find "$app" -type f -print0 2>/dev/null)

    if [[ "$mode" == "check" ]]; then
        (( unresolved == 0 )) || return 1
        return 0
    fi
    echo "  re-linked $relinked binaries against the bundle's Frameworks"
    (( dropped )) && echo "  dropped $dropped build-host rpath entries"
}

prune_release_payload() {
    local app="$1"
    local qml="$app/Contents/Resources/qml"
    [[ -d "$qml" ]] || return 0

    local mod family name pruned=0
    local -a modules=(
        "QtQuick/tooling"           # LiveReload, for developing QML
        "QtQuick/Controls/designer" # Qt Quick Controls plugin for Qt Designer
        "QtQuick/Scene2D"           # Qt3D — framework not deployed
        "QtQuick/Scene3D"           # Qt3D — framework not deployed
        "QtQuick/Timeline"          # QtQuickTimeline — framework not deployed
        "QtQuick/VirtualKeyboard"   # QtVirtualKeyboard — framework not deployed
        "Qt/labs"                   # experimental, unimported
    )
    for mod in "${modules[@]}"; do
        [[ -d "$qml/$mod" ]] || continue
        family="${mod%%/*}"
        name="${mod##*/}"
        if [[ -d "$SCRIPT_DIR/ui" ]] && \
           grep -rqsE "^[[:space:]]*import[[:space:]]+$family\.$name([^0-9A-Za-z_]|$)" "$SCRIPT_DIR/ui"; then
            echo "  keeping $mod — imported by the app"
            continue
        fi
        rm -rf "${qml:?}/$mod"
        echo "  pruned $mod"
        pruned=$((pruned + 1))
    done
    (( pruned )) || echo "  no development payload to prune"
}

prune_release_macpayload() {
    local app="$1"
    local qml="$app/Contents/Resources/qml"
    local fw="$app/Contents/Frameworks"
    local quick="$app/Contents/PlugIns/quick"
    local before after
    before="$(du -sk "$app" | cut -f1)"

    # 1. Chromium locale packs (~44MB). English strings live in
    #    qtwebengine_resources.pak; only the en-* overrides are separate files.
    local locales="$fw/QtWebEngineCore.framework/Versions/A/Resources/qtwebengine_locales"
    if [[ -d "$locales" ]]; then
        local keep_locales="${QT_ILLUMINATE_KEEP_LOCALES:-en-US en-GB}"
        local -a keep=($keep_locales)
        local pak name
        for pak in "$locales"/*.pak; do
            [[ -e "$pak" ]] || continue
            name="$(basename "$pak")"
            local wanted=0 k
            for k in "${keep[@]}"; do
                [[ "$name" == "$k.pak" ]] && { wanted=1; break; }
            done
            if (( ! wanted )); then
                rm -f "$pak"
                echo "  pruned locale $name"
            fi
        done
    fi

    local -a styles=(Imagine Material Universal FluentWinUI3 iOS)
    local style lower
    for style in "${styles[@]}"; do
        lower="$(printf '%s' "$style" | tr '[:upper:]' '[:lower:]')"
        rm -rf "${qml:?}/QtQuick/Controls/$style"
        rm -f  "$quick"/libqtquickcontrols2"$lower"style*plugin.dylib
        rm -rf "$fw"/QtQuickControls2"$style"*.framework
    done
    echo "  pruned ${#styles[@]} unused Quick Controls styles"

    rm -rf "${qml:?}/QtQuick/Particles" "${qml:?}/QtQuick/VectorImage"
    rm -f "$quick"/libparticlesplugin.dylib \
          "$quick"/libqquickvectorimageplugin.dylib \
          "$quick"/libqquickvectorimagehelpersplugin.dylib
    rm -rf "$fw"/QtQuickParticles.framework "$fw"/QtQuickVectorImage.framework \
           "$fw"/QtQuickVectorImageHelpers.framework "$fw"/QtQuickVectorImageGenerator.framework
    echo "  pruned 2 unimported QtQuick modules"

    rm -f "$quick"/libq*vkb*plugin.dylib "$quick"/libvirtualkeyboardplugin.dylib \
          "$app/Contents/PlugIns/platforminputcontexts/libqtvirtualkeyboardplugin.dylib"
    rm -rf "$app/Contents/PlugIns/multimedia" "${fw:?}/QtMultimedia.framework"
    echo "  pruned VirtualKeyboard + Multimedia"

    rm -f "$quick"/libqtquicktimeline*.dylib "$quick"/libqtquickscene2dplugin.dylib \
          "$quick"/libqtquickscene3dplugin.dylib "$quick"/libquicktoolingplugin.dylib \
          "$quick"/libqtqmlstatemachineplugin.dylib
    # The QML module dirs must go too: their qmldir/plugin dylib symlinks point
    # at the plugins just removed, leaving dangling symlinks that fail the
    # dangling-link check below.
    rm -rf "${qml:?}/QtQml/StateMachine" "${qml:?}/QtQml/Timeline" \
           "${qml:?}/QtQuick/Scene2D" "${qml:?}/QtQuick/Scene3D"
    echo "  pruned timeline/scene2d/scene3d/tooling/statemachine plugins"

    rm -f "$app/Contents/PlugIns/position/libqtposition_nmea.dylib"
    rm -rf "${fw:?}/QtSerialPort.framework"
    echo "  pruned NMEA positioning + QtSerialPort"

    after="$(du -sk "$app" | cut -f1)"
    printf '  bundle %.0fMB → %.0fMB (-%.0fMB)\n' \
        "$(awk "BEGIN{print $before/1024}")" \
        "$(awk "BEGIN{print $after/1024}")" \
        "$(awk "BEGIN{print ($before-$after)/1024}")"
}

dep_resolves() {
    local dir="$1" dep="$2"
    [[ -e "$dir/$dep" ]] && return 0
    [[ -e "$dir/$dep.framework/Versions/A/$dep" ]] && return 0
    [[ -e "$dir/$dep.framework/Versions/Current/$dep" ]] && return 0
    [[ -e "$dir/$dep.framework/$dep" ]] && return 0
    return 1
}

verify_bundle_deps() {
    local app="$1"
    local fw_dir; fw_dir="$(cd "$app/Contents/Frameworks" && pwd -P)"
    local missing=0 bin dep rest rpath dir found base
    while IFS= read -r bin; do
        file -b "$bin" 2>/dev/null | grep -q "Mach-O" || continue
        base="$(dirname "$bin")"
        while IFS= read -r dep; do
            case "$dep" in
                @rpath/*) rest="${dep#@rpath/}" ;;
                *) continue ;;
            esac
            dep_resolves "$fw_dir" "$rest" && continue
            found=0
            while IFS= read -r rpath; do
                case "$rpath" in
                    @loader_path/*)     dir="$base/${rpath#@loader_path/}" ;;
                    @executable_path/*) dir="$base/${rpath#@executable_path/}" ;;
                    /*)                 dir="$rpath" ;;
                    *)                  continue ;;
                esac
                if dep_resolves "$dir" "$rest"; then found=1; break; fi
            done < <(bundle_rpaths "$bin")
            if (( ! found )); then
                echo "  ${bin#"$app"/} → $dep"
                missing=1
            fi
        done < <(otool -L "$bin" 2>/dev/null | tail -n +2 | awk 'NF { print $1 }')
    done < <(find "$app" -type f)
    (( missing )) && return 1
    return 0
}

verify_qml_modules() {
    local qml="$1"
    local missing=0 ref f
    local -a files=()
    while IFS= read -r f; do
        files+=("$f")
    done < <(find "$qml" -name 'qmldir' 2>/dev/null)
    (( ${#files[@]} )) || return 0
    while IFS= read -r ref; do
        [[ -d "$qml/$(printf '%s' "$ref" | tr '.' '/')" ]] && continue
        echo "  missing QML module: $ref"
        missing=1
    done < <(grep -hoE "^[[:space:]]*(optional[[:space:]]+)?(import|depends)[[:space:]]+QtQuick\.[A-Za-z0-9_.]+" \
                  "${files[@]}" 2>/dev/null | awk '$1 != "optional" { print $NF }' | sort -u)
    (( missing )) && return 1
    return 0
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

check_deps() {
    MISSING=()
    has_compiler || MISSING+=("C++ compiler")
    command -v cmake >/dev/null 2>&1 || MISSING+=("cmake")
    if (( IS_LINUX )); then
        command -v ninja >/dev/null 2>&1 || MISSING+=("ninja")
    fi
    QT_PREFIX="$(find_qt)"
    if [[ -z "$QT_PREFIX" ]]; then
        MISSING+=("Qt 6")
    elif ! qt_has_webengine "$QT_PREFIX"; then
        MISSING+=("Qt WebEngine (Qt found at $QT_PREFIX)")
    fi
}

check_deps
if (( ${#MISSING[@]} )); then
    echo "✗ Missing build dependencies:"
    printf '    • %s\n' "${MISSING[@]}"
    echo
    echo "  This script builds and packages the app; it doesn't set up your"
    echo "  toolchain. Install the above yourself, then re-run:"
    if (( IS_MAC )); then
        echo "    • Xcode Command Line Tools — xcode-select --install"
        echo "    • cmake and Qt 6 with WebEngine — brew install cmake qt"
        echo "      or the Qt installer: https://www.qt.io/download-qt-installer"
    else
        echo "    • a C++ compiler, cmake and ninja from your distro's packages"
        echo "    • Qt 6 with WebEngine, WebChannel and the QML modules"
        echo "      (exact package names vary by distro — check your package"
        echo "      manager, or use https://www.qt.io/download-qt-installer)"
    fi
    if [[ -n "$QT_PREFIX" ]]; then
        echo "  (Qt was found at $QT_PREFIX, but its WebEngine module wasn't.)"
    fi
    echo "  Qt installed somewhere nonstandard? Point QT_DIR at its prefix."
    exit 1
fi

BUILD_TYPE="Release"
(( DO_DEV )) && BUILD_TYPE="Debug"

SCRIPT_DIR="${QT_ILLUMINATE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
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

echo "→ Using Qt at: $QT_PREFIX"

# ── Configure ────────────────────────────────────────────────────────────────
CONFIGURED_TYPE=""
CONFIGURED_PREFIX=""
if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    CONFIGURED_TYPE="$(sed -n 's/^CMAKE_BUILD_TYPE:[A-Z]*=//p' "$BUILD_DIR/CMakeCache.txt")"
    CONFIGURED_PREFIX="$(sed -n 's/^CMAKE_PREFIX_PATH:[A-Z]*=//p' "$BUILD_DIR/CMakeCache.txt")"
fi

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]] || [[ "$CONFIGURED_TYPE" != "$BUILD_TYPE" ]] \
        || [[ "$CONFIGURED_PREFIX" != "$QT_PREFIX" ]]; then
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

clean_app_data

[[ -n "$APP_BUNDLE" ]] && rm -rf "$APP_BUNDLE"

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
    if [[ -z "$APP_VERSION" ]]; then
        echo "⚠ Could not read a version from CMakeLists.txt; using 0.0.0 for the package name."
        APP_VERSION="0.0.0"
    fi
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

        DEPLOY_LOG="$(mktemp)"
        if ! "$MACDEPLOYQT" "$STAGED_APP" -qmldir="$SCRIPT_DIR/ui" \
                        -qmlimport="$QML_IMPORTS" 2>"$DEPLOY_LOG"; then
            echo "✗ macdeployqt failed:"
            cat "$DEPLOY_LOG"
            rm -f "$DEPLOY_LOG"
            exit 1
        fi
        grep -vE 'Cannot resolve rpath|using QList\(|codesign verification error|invalid signature \(code or signature' \
            "$DEPLOY_LOG" >&2 || true
        rm -f "$DEPLOY_LOG"
        rm -rf "$QML_IMPORTS"

        echo "→ Re-pointing leftover absolute dependencies…"
        relink_bundle_deps "$STAGED_APP"

        echo "→ Pruning development payload…"
        prune_release_payload "$STAGED_APP"

        echo "→ Pruning unused Qt payload…"
        prune_release_macpayload "$STAGED_APP"

        echo "→ Verifying no pruned library is still linked…"
        if ! BROKEN_DEPS="$(verify_bundle_deps "$STAGED_APP")"; then
            echo "✗ Deployed bundle has unresolvable dependencies:"
            echo "$BROKEN_DEPS" | head -20
            exit 1
        fi

        echo "→ Verifying no pruned QML module is still imported…"
        if ! MISSING_QML="$(verify_qml_modules "$STAGED_APP/Contents/Resources/qml")"; then
            echo "✗ Deployed bundle is missing QML modules still imported:"
            echo "$MISSING_QML" | head -20
            exit 1
        fi

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
        [[ -f "$STAGED_APP/Contents/Resources/AppIcon.icns" ]] || {
            echo "✗ Deployed bundle is missing Contents/Resources/AppIcon.icns"
            exit 1
        }

        echo "→ Signing (${CODESIGN_IDENTITY:-ad-hoc})…"
        codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$STAGED_APP"
        codesign --verify --deep --strict "$STAGED_APP" || {
            echo "✗ Deployed bundle failed signature verification."
            exit 1
        }

        STRAY_LINKS="$(relink_bundle_deps --check "$STAGED_APP")" || true
        if [[ -n "$STRAY_LINKS" ]]; then
            echo "✗ Deployed bundle still references build-host libraries:"
            echo "$STRAY_LINKS" | head -10
            exit 1
        fi

        DMG_PATH="$DIST_DIR/QT_Illuminate-${APP_VERSION}-macos-$(uname -m).dmg"
        echo "→ Creating disk image…"
        ln -s /Applications "$STAGE_DIR/Applications"
        rm -f "$DMG_PATH"
        # hdiutil create is deprecated in favour of diskutil's image create
        DMG_LOG="$(diskutil image create from "$STAGE_DIR" "$DMG_PATH" \
                --volumeName "QT_Illuminate" --format UDZO 2>&1 >/dev/null)" || {
            echo "✗ diskutil image create failed:"
            echo "$DMG_LOG"
            exit 1
        }
        rm -rf "$DIST_DIR/QT_Illuminate.app"
        mv "$STAGED_APP" "$DIST_DIR/"
        rm -rf "$STAGE_DIR"
        echo "✓ Package: $DMG_PATH"
        echo "  App:     $DIST_DIR/QT_Illuminate.app"
    else
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