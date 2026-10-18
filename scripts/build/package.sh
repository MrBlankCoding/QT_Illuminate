# Platform package creation. Variables are prepared by build.sh.

package_application() {

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
        [[ -f "$STAGED_APP/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" ]] || {
            echo "✗ Deployed bundle is missing Chromium Embedded Framework.framework"
            exit 1
        }
        for _helper in "" " (Alerts)" " (GPU)" " (Plugin)" " (Renderer)"; do
            [[ -x "$STAGED_APP/Contents/Frameworks/QT_Illuminate Helper$_helper.app/Contents/MacOS/QT_Illuminate Helper$_helper" ]] || {
                echo "✗ Deployed bundle is missing QT_Illuminate Helper$_helper.app"
                exit 1
            }
        done
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
        echo "  Extract to / (or a prefix) — requires libcef and its dependencies."
    fi
}
