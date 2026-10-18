# Bundle verification and dependency relocation helpers.

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
