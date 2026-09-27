import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// one per tab: the internal page or the web view (+ devtools)
Item {
    id: tabSlot
    required property int index
    required property var model
    required property var browserWindow
    required property var viewStack
    anchors.fill: parent
    visible: index === Browser.tabModel.activeIndex

    readonly property bool isInternalPage: InternalPages.isInternal(model.url.toString())
    onIsInternalPageChanged: if (isInternalPage) Browser.onRenderProcessPidChanged(index, 0)
    function syncRenderPid() {
        Browser.onRenderProcessPidChanged(tabSlot.index, tabSlot.webView ? tabSlot.webView.renderProcessPid : 0)
    }

    readonly property int discardAfterMs: 5 * 60 * 1000
    property bool discardable: false
    onVisibleChanged: {
        if (visible) {
            discardable = false
            browserWindow.pointerLockActive = tabSlot.pointerLocked
        } else if (tabSlot.pointerLocked) {
            tabSlot.releaseLock()
        }
    }

    function releaseLock() {
        tabSlot.pointerLocked = false
        const wv = tabSlot.webView
        if (wv)
            wv.runJavaScript("window.__illuminate__forceExit && window.__illuminate__forceExit()")
    }
    Timer {
        interval: tabSlot.discardAfterMs
        running: !tabSlot.visible && tabSlot.webView !== null
        onTriggered: tabSlot.discardable = true
    }
    property bool devToolsOpen: false
    readonly property CefBrowser webView: webLoader.item as CefBrowser
    onWebViewChanged: viewStack.refreshActiveWebView()
    // user could change this
    property string devToolsDock: "right"
    readonly property bool devToolsVertical: devToolsDock === "bottom"
    property real devToolsSize: devToolsVertical ? height * 0.35 : Math.min(480, width * 0.4)
    readonly property real devToolsMinSize: 200
    readonly property real pageMinSize: 200
    readonly property real clampedDevToolsSize: Math.max(devToolsMinSize,
        Math.min(devToolsSize, (devToolsVertical ? height : width) - pageMinSize))
    readonly property string devToolsDockMarker: "__illuminate_devtools_dock__ "
    onDevToolsDockChanged: devToolsSize = devToolsVertical ? height * 0.35 : Math.min(480, width * 0.4)

    readonly property string plockReqMarker: "__illuminate_plock_req__"
    readonly property string plockExitMarker: "__illuminate_plock_exit__"
    property bool pointerLocked: false
    onPointerLockedChanged: {
        if (pointerLocked)
            browserWindow.pointerLockEmu.begin()
        else
            browserWindow.pointerLockEmu.end()
        if (tabSlot.visible)
            browserWindow.pointerLockActive = tabSlot.pointerLocked
        if (pointerLocked)
            pointerLockHint.flash()
        else
            pointerLockHint.opacity = 0
    }

    // QML XHR can read embedded resources synchronously
    function readResource(path) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", path, false);
        xhr.send();
        return xhr.responseText;
    }

    readonly property string pointerLockShimSource: tabSlot.readResource("qrc:/QT_Illuminate/ui/ui/resources/js/pointer-lock-shim.js")

    Loader {
        anchors.fill: parent
        active: tabSlot.isInternalPage
        visible: tabSlot.isInternalPage
        source: tabSlot.isInternalPage ? InternalPages.qmlSource(tabSlot.model.url.toString()) : ""
        onLoaded: Browser.onTitleChanged(tabSlot.index, InternalPages.title(tabSlot.model.url.toString()))
    }

    Loader {
        id: webLoader
        x: tabSlot.devToolsOpen && tabSlot.devToolsDock === "left" ? tabSlot.clampedDevToolsSize : 0
        y: 0
        width: tabSlot.devToolsOpen && !tabSlot.devToolsVertical ? parent.width - tabSlot.clampedDevToolsSize : parent.width
        height: tabSlot.devToolsOpen && tabSlot.devToolsVertical ? parent.height - tabSlot.clampedDevToolsSize : parent.height
        // restored tabs stay suspended (no view, no renderer) until first shown
        active: !tabSlot.isInternalPage && !tabSlot.model.suspended
        visible: !tabSlot.isInternalPage

        onLoaded: {
            const u = tabSlot.model.url;
            if (u && u.toString() !== "" && !tabSlot.isInternalPage)
                item.url = u;
        }

        sourceComponent: Component {
            CefBrowser {
                id: webView
                anchors.fill: parent

                // set once at creation; a profile switch replaces every tab
                profile: Browser.webProfile
                visible: tabSlot.index === Browser.tabModel.activeIndex
                lifecycleState: webView.visible
                    ? CefBrowser.Active
                    : (webView.recommendedState === CefBrowser.Discarded
                        ? (tabSlot.discardable ? CefBrowser.Discarded : CefBrowser.Frozen)
                        : webView.recommendedState)
                onLifecycleStateChanged: tabSlot.syncRenderPid()

                // avoids a white flash before the first paint
                backgroundColor: Theme.bg

                // JS injection: hide WebGPU and install pointer-lock shim
                // CEF: scripts injected via CefBrowserWrapper on OnLoadStart
                Component.onCompleted: {
                    Logger.info("WebView", "Tab " + tabSlot.index + " created, url=" + tabSlot.model.url);
                    // Inject scripts now that browser is ready
                    webView.runJavaScript("delete Navigator.prototype.gpu;");
                    webView.runJavaScript(tabSlot.pointerLockShimSource);
                }

                onLoadingChanged: function () {
                    Browser.onLoadingChanged(tabSlot.index, webView.loading);
                    tabSlot.syncRenderPid();
                    if (webView.loading)
                        Logger.info("WebView", "Tab " + tabSlot.index + " loading: " + webView.url);
                }

                onJavaScriptConsoleMessage: function (level, message, lineNumber, sourceId) {
                    const msg = String(message)
                    if (msg.startsWith(tabSlot.plockReqMarker)) {
                        tabSlot.pointerLocked = true
                        return
                    }
                    if (msg.startsWith(tabSlot.plockExitMarker)) {
                        tabSlot.pointerLocked = false
                        return
                    }
                    if (level === 0)
                        return
                    const text = level + "/" + sourceId + ":" + lineNumber + " " + msg
                    if (level >= 3)
                        Logger.error("WebView", text)
                    else
                        Logger.warning("WebView", text)
                }

                onUrlChanged: function () {
                    Browser.onUrlChanged(tabSlot.index, webView.url.toString());
                    Logger.debug("WebView", "Tab " + tabSlot.index + " url → " + webView.url);
                }

                onLoadProgressChanged: function (p) { Browser.onLoadProgressChanged(tabSlot.index, p) }
                onRenderProcessPidChanged: tabSlot.syncRenderPid()
                onTitleChanged: Browser.onTitleChanged(tabSlot.index, webView.title)
                onIconChanged: Browser.onIconUrlChanged(tabSlot.index, webView.icon.toString())

                onNewWindowRequested: function (url) {
                    Browser.onNewWindowRequested(tabSlot.index, url.toString());
                }

                // pages calling window.print() open the system print dialog
                onPrintRequested: browserWindow.openSystemPrintFor(webView)
                onPdfPrintingFinished: (filePath, success) => browserWindow.onPdfPrintingFinished(filePath, success)

                onContextMenuRequested: function (request) {
                    contextMenu.request = request;
                    contextMenu.popup();
                }

                onPermissionRequested: function (permission) {
                    tabSlot.handlePermission(permission)
                }

                ContextMenu {
                    id: contextMenu
                    webView: webView
                    onToggleDevTools: tabSlot.devToolsOpen = !tabSlot.devToolsOpen
                    onInspectElement: {
                        tabSlot.devToolsOpen = true
                        Qt.callLater(() => webView.triggerWebAction(CefBrowser.InspectElement))
                    }
                }

                Connections {
                    target: Browser
                    function onLoadRequested(tabIndex, url) {
                        if (tabIndex !== tabSlot.index)
                            return;
                        if (webLoader.item)
                            webLoader.item.url = url;
                    }
                    function onNavigationRequested(action) {
                        if (tabSlot.index !== Browser.tabModel.activeIndex)
                            return;
                        if (action === "back")
                            webView.goBack();
                        else if (action === "forward")
                            webView.goForward();
                        else if (action === "reload")
                            webView.reload();
                        else if (action === "devtools")
                            tabSlot.devToolsOpen = !tabSlot.devToolsOpen;
                    }
                }
            }
        }
    }

    MouseArea {
        id: lockOverlay
        visible: tabSlot.pointerLocked
        x: webLoader.x
        y: webLoader.y
        width: webLoader.width
        height: webLoader.height
        z: 5
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
    }

    Loader {
        id: devToolsLoader
        x: tabSlot.devToolsDock === "right" ? parent.width - width : 0
        y: tabSlot.devToolsVertical ? parent.height - height : 0
        width: tabSlot.devToolsVertical ? parent.width : tabSlot.clampedDevToolsSize
        height: tabSlot.devToolsVertical ? tabSlot.clampedDevToolsSize : parent.height
        active: tabSlot.devToolsOpen
        visible: tabSlot.devToolsOpen

        sourceComponent: Component {
            // CEF: dev tools opened via CefBrowserHost::ShowDevTools() into a popup.
            // The CefBrowser wrapper exposes showDevTools()/closeDevTools() called
            // by devToolsOpen toggle; no separate embedded view needed here.
            Item {
                anchors.fill: parent
                Component.onCompleted: {
                    if (tabSlot.webView)
                        tabSlot.webView.showDevTools()
                }
                Component.onDestruction: {
                    if (tabSlot.webView)
                        tabSlot.webView.closeDevTools()
                }
            }
        }
    }

    Rectangle {
        id: devToolsSplitter
        visible: tabSlot.devToolsOpen
        z: 10
        color: splitterArea.pressed || splitterArea.containsMouse ? Theme.accent : Theme.border
        x: tabSlot.devToolsDock === "right" ? devToolsLoader.x - width / 2
         : tabSlot.devToolsDock === "left" ? devToolsLoader.width - width / 2 : 0
        y: tabSlot.devToolsVertical ? devToolsLoader.y - height / 2 : 0
        width: tabSlot.devToolsVertical ? parent.width : 1
        height: tabSlot.devToolsVertical ? 1 : parent.height

        MouseArea {
            id: splitterArea
            // wider than the 1px line so it's easy to grab
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            cursorShape: tabSlot.devToolsVertical ? Qt.SizeVerCursor : Qt.SizeHorCursor
            preventStealing: true

            onPositionChanged: function (mouse) {
                if (!pressed)
                    return
                const p = mapToItem(tabSlot, mouse.x, mouse.y)
                if (tabSlot.devToolsDock === "right")
                    tabSlot.devToolsSize = tabSlot.width - p.x
                else if (tabSlot.devToolsDock === "left")
                    tabSlot.devToolsSize = p.x
                else
                    tabSlot.devToolsSize = tabSlot.height - p.y
            }
        }
    }

    Rectangle {
        id: pointerLockHint
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 24
        width: hintText.implicitWidth + 32
        height: 36
        radius: height / 2
        color: Theme.surface
        border.color: Theme.border
        border.width: 1
        opacity: 0
        visible: opacity > 0
        z: 50

        function flash() {
            opacity = 1
            hintTimer.restart()
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durationFast
            }
        }

        Timer {
            id: hintTimer
            interval: 3000
            onTriggered: pointerLockHint.opacity = 0
        }

        Text {
            id: hintText
            anchors.centerIn: parent
            text: "Press Esc to show your cursor"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeS
        }
    }

    // ── permission prompt ─────────────────────────────────────────────
    // decisions and OS access checks live in Permissions (PermissionHandler);
    // this only shows the prompt when nothing was remembered
    property var pendingPermission: null
    property string pendingPermissionLabel: ""
    // OS resource blocking the pending request (Permissions.SystemResource), or -1
    property int pendingBlockedResource: -1

    function handlePermission(permission) {
        if (Permissions.resolve(permission))
            return
        const type = permission.permissionType
        tabSlot.pendingPermission = permission
        tabSlot.pendingPermissionLabel = Permissions.labelForType(type)
        tabSlot.pendingBlockedResource = Permissions.blockedResourceForType(type)
        rememberChk.checked = false
        permissionPopup.open()
    }

    function applyPermission(allow) {
        const p = tabSlot.pendingPermission
        if (!p)
            return
        Permissions.respond(p, allow, rememberChk.checked)
        tabSlot.pendingPermission = null
        permissionPopup.close()
    }

    Connections {
        target: Permissions
        enabled: tabSlot.pendingPermission !== null
        function onSystemAccessChanged() {
            tabSlot.pendingBlockedResource =
                Permissions.blockedResourceForType(tabSlot.pendingPermission.permissionType)
        }
    }

    Popup {
        id: permissionPopup
        modal: true
        focus: true
        padding: 0
        width: 320
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        background: Rectangle {
            radius: 16
            color: Theme.bg
            border.color: Theme.border
            border.width: 1
        }

        ColumnLayout {
            anchors.margins: 20
            anchors.fill: parent
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: (tabSlot.pendingPermission ? tabSlot.pendingPermission.origin.host : "") + " " + tabSlot.pendingPermissionLabel + "?"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                color: Theme.text
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: tabSlot.pendingBlockedResource >= 0
                text: Permissions.labelForResource(tabSlot.pendingBlockedResource)
                      + " access is turned off for Illuminate in your system settings."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS
                color: Theme.danger
                wrapMode: Text.WordWrap
            }

            PillButton {
                visible: tabSlot.pendingBlockedResource >= 0
                text: "Open System Settings"
                textColor: Theme.text
                fillColor: Theme.surfaceHigh
                hoverFillColor: Theme.surface
                onClicked: Permissions.openSystemSettings(tabSlot.pendingBlockedResource)
            }

            CheckBox {
                id: rememberChk
                text: "Remember this choice"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS
                palette.windowText: Theme.textMuted
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                PillButton {
                    text: "Allow"
                    textColor: "white"
                    fillColor: Theme.accent
                    hoverFillColor: Qt.darker(Theme.accent, 1.1)
                    onClicked: tabSlot.applyPermission(true)
                }
                PillButton {
                    text: "Deny"
                    textColor: Theme.textMuted
                    fillColor: Theme.surfaceHigh
                    hoverFillColor: Theme.surface
                    onClicked: tabSlot.applyPermission(false)
                }
            }
        }
    }
}