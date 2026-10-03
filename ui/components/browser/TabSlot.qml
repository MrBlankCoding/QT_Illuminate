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

    readonly property int discardAfterMs: Prefs.autoUnloadEnabled
        ? Math.max(1, Prefs.autoUnloadMinutes) * 60 * 1000
        : 0
    property bool discardable: false
    onVisibleChanged: {
        if (visible) {
            discardable = false
            browserWindow.pointerLockActive = tabSlot.pointerLocked
        } else if (tabSlot.pointerLocked) {
            tabSlot.releaseLock()
        }
    }
    Component.onDestruction: {
        if (tabSlot.pointerLocked && tabSlot.browserWindow) {
            tabSlot.browserWindow.pointerLockEmu.end()
            if (tabSlot.visible)
                tabSlot.browserWindow.pointerLockActive = false
        }
    }

    function releaseLock() {
        tabSlot.pointerLocked = false
        const wv = tabSlot.webView
        if (wv)
            wv.runJavaScript("window.__illuminate__forceExit && window.__illuminate__forceExit()")
    }
    Timer {
        interval: Math.max(1, tabSlot.discardAfterMs)
        running: tabSlot.discardAfterMs > 0 && !tabSlot.visible && tabSlot.webView !== null
        onTriggered: tabSlot.discardable = true
    }
    property bool devToolsOpen: false
    // point for the next "Inspect", in page coordinates; (0,0) = none
    property point devToolsInspectAt: Qt.point(0, 0)
    readonly property CefBrowser webView: webLoader.item as CefBrowser
    onWebViewChanged: {
        viewStack.refreshActiveWebView()
        if (tabSlot.devToolsOpen)
            tabSlot.openDevTools(devToolsLoader.item)
    }

    function openDevTools(view) {
        const wv = tabSlot.webView
        if (!wv || !view)
            return
        wv.devToolsView = view
        wv.showDevTools(tabSlot.devToolsInspectAt)
        tabSlot.devToolsInspectAt = Qt.point(0, 0)
    }

    function closeDevTools() {
        const wv = tabSlot.webView
        if (!wv)
            return
        wv.closeDevTools()
        wv.devToolsView = null
    }

    // user could change this
    property string devToolsDock: "right"
    readonly property bool devToolsVertical: devToolsDock === "bottom"
    property real devToolsSize: devToolsVertical ? height * 0.35 : Math.min(480, width * 0.4)
    readonly property real devToolsMinSize: 200
    readonly property real pageMinSize: 200
    readonly property real splitterGap: 6
    readonly property real splitterSpace: devToolsOpen ? splitterGap : 0
    readonly property real clampedDevToolsSize: Math.max(devToolsMinSize,
        Math.min(devToolsSize, (devToolsVertical ? height : width) - pageMinSize - splitterGap))
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
            pointerLockHint.close()
    }

    Loader {
        anchors.fill: parent
        active: tabSlot.isInternalPage
        visible: tabSlot.isInternalPage
        source: tabSlot.isInternalPage ? InternalPages.qmlSource(tabSlot.model.url.toString()) : ""
        onLoaded: Browser.onTitleChanged(tabSlot.index, InternalPages.title(tabSlot.model.url.toString()))
    }

    Loader {
        id: webLoader
        x: tabSlot.devToolsOpen && tabSlot.devToolsDock === "left" ? tabSlot.clampedDevToolsSize + tabSlot.splitterSpace : 0
        y: 0
        width: tabSlot.devToolsOpen && !tabSlot.devToolsVertical ? parent.width - tabSlot.clampedDevToolsSize - tabSlot.splitterSpace : parent.width
        height: tabSlot.devToolsOpen && tabSlot.devToolsVertical ? parent.height - tabSlot.clampedDevToolsSize - tabSlot.splitterSpace : parent.height
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
                profile: Browser.webProfile
                visible: tabSlot.index === Browser.tabModel.activeIndex
                inputSuppressed: tabSlot.browserWindow.inputOverlayOpen
                    && tabSlot.index === Browser.tabModel.activeIndex
                lifecycleState: webView.visible
                    ? CefBrowser.Active
                    : (tabSlot.discardable ? CefBrowser.Discarded : CefBrowser.Frozen)
                onLifecycleStateChanged: tabSlot.syncRenderPid()
                backgroundColor: Theme.bg
                cornerRadius: tabSlot.viewStack.cornerRadius
                Component.onCompleted: {
                    Logger.debug("WebView", "Tab " + tabSlot.index + " created");
                }

                onLoadingChanged: function () {
                    Browser.onLoadingChanged(tabSlot.index, webView.loading);
                    tabSlot.syncRenderPid();
                    if (webView.loading)
                        Logger.debug("WebView", "Tab " + tabSlot.index + " loading");
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
                }

                onLoadProgressChanged: function (p) { Browser.onLoadProgressChanged(tabSlot.index, p) }
                onRenderProcessPidChanged: tabSlot.syncRenderPid()
                onTitleChanged: Browser.onTitleChanged(tabSlot.index, webView.title)
                onIconChanged: Browser.onIconUrlChanged(tabSlot.index, webView.icon.toString())

                onNewWindowRequested: function (url) {
                    Browser.onNewWindowRequested(tabSlot.index, url.toString());
                }

                // pages calling window.print() open the system print dialog
                onPrintRequested: tabSlot.browserWindow.openSystemPrintFor(webView)
                onPdfPrintingFinished: (filePath, success) => tabSlot.browserWindow.onPdfPrintingFinished(filePath, success)

                onContextMenuRequested: function (request) {
                    contextMenu.request = request;
                    contextMenu.popup();
                }

                onPermissionRequested: function (permission) {
                    tabSlot.handlePermission(permission)
                }

                WebContextMenu {
                    id: contextMenu
                    webView: webView
                    onToggleDevTools: tabSlot.devToolsOpen = !tabSlot.devToolsOpen
                    onInspectElement: (x, y) => {
                        // stash the point first: the dock opens DevTools itself
                        // once it exists, and picks this up
                        tabSlot.devToolsInspectAt = Qt.point(x, y)
                        tabSlot.devToolsOpen = true
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

    Loader {
        id: devToolsLoader
        x: tabSlot.devToolsDock === "right" ? parent.width - width : 0
        y: tabSlot.devToolsVertical ? parent.height - height : 0
        width: tabSlot.devToolsVertical ? parent.width : tabSlot.clampedDevToolsSize
        height: tabSlot.devToolsVertical ? tabSlot.clampedDevToolsSize : parent.height
        active: tabSlot.devToolsOpen
        visible: tabSlot.devToolsOpen

        sourceComponent: Component {
            CefBrowser {
                id: devToolsView
                anchors.fill: parent
                externalBrowser: true
                backgroundColor: Theme.bg
                cornerRadius: tabSlot.viewStack.cornerRadius

                Component.onCompleted: Qt.callLater(() => tabSlot.openDevTools(devToolsView))
                Component.onDestruction: tabSlot.closeDevTools()
            }
        }
    }

    // the gap between page and DevTools, with a 1px line in the middle
    MouseArea {
        id: splitterArea
        visible: tabSlot.devToolsOpen
        z: 10
        x: tabSlot.devToolsDock === "right" ? devToolsLoader.x - width
         : tabSlot.devToolsDock === "left" ? devToolsLoader.width : 0
        y: tabSlot.devToolsVertical ? devToolsLoader.y - height : 0
        width: tabSlot.devToolsVertical ? parent.width : tabSlot.splitterGap
        height: tabSlot.devToolsVertical ? tabSlot.splitterGap : parent.height
        hoverEnabled: true
        cursorShape: tabSlot.devToolsVertical ? Qt.SizeVerCursor : Qt.SizeHorCursor
        preventStealing: true

        onPositionChanged: function (mouse) {
            if (!pressed)
                return
            const p = mapToItem(tabSlot, mouse.x, mouse.y)
            const half = tabSlot.splitterGap / 2
            if (tabSlot.devToolsDock === "right")
                tabSlot.devToolsSize = tabSlot.width - p.x - half
            else if (tabSlot.devToolsDock === "left")
                tabSlot.devToolsSize = p.x - half
            else
                tabSlot.devToolsSize = tabSlot.height - p.y - half
        }

        Rectangle {
            anchors.centerIn: parent
            width: tabSlot.devToolsVertical ? parent.width : 1
            height: tabSlot.devToolsVertical ? 1 : parent.height
            color: splitterArea.pressed || splitterArea.containsMouse ? Theme.accent : Theme.border
        }
    }

    Popup {
        id: pointerLockHint
        popupType: Popup.Window
        modal: false
        focus: false
        closePolicy: Popup.NoAutoClose
        x: Math.round((tabSlot.width - width) / 2)
        y: 24
        width: hintText.implicitWidth + 32
        height: 36
        padding: 0

        function flash() {
            open()
            hintTimer.restart()
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationFast }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
        }

        Timer {
            id: hintTimer
            interval: 3000
            onTriggered: pointerLockHint.close()
        }

        background: Rectangle {
            radius: height / 2
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
        }

        contentItem: Text {
            id: hintText
            text: "Press Esc to show your cursor"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeS
        }
    }

    property var pendingPermission: null
    property string pendingPermissionLabel: ""
    property int pendingBlockedResource: -1
    property var permissionQueue: []

    function handlePermission(permission) {
        if (Permissions.resolve(permission))
            return
        if (tabSlot.pendingPermission || permissionPopup.visible) {
            tabSlot.permissionQueue.push(permission)
            return
        }
        tabSlot.showPermission(permission)
    }

    function showPermission(permission) {
        const type = permission.permissionType
        tabSlot.pendingPermission = permission
        tabSlot.pendingPermissionLabel = Permissions.labelForType(type)
        tabSlot.pendingBlockedResource = Permissions.blockedResourceForType(type)
        rememberChk.checked = false
        permissionPopup.open()
    }

    function showNextPermission() {
        if (tabSlot.pendingPermission || permissionPopup.visible)
            return
        while (tabSlot.permissionQueue.length > 0) {
            const p = tabSlot.permissionQueue.shift()
            if (!p || p.permissionType === undefined || Permissions.resolve(p))
                continue
            tabSlot.showPermission(p)
            return
        }
    }

    function applyPermission(allow) {
        const p = tabSlot.pendingPermission
        if (!p)
            return
        Permissions.respond(p, allow, rememberChk.checked)
        tabSlot.pendingPermission = null
        permissionPopup.close()
    }

    onPendingPermissionChanged: {
        if (!tabSlot.pendingPermission && permissionPopup.visible)
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
        popupType: Popup.Window
        modal: true
        focus: true
        padding: 20
        width: 320
        x: Math.round((tabSlot.width - width) / 2)
        y: Math.round((tabSlot.height - height) / 2)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: {
            const p = tabSlot.pendingPermission
            tabSlot.pendingPermission = null
            if (p)
                p.deny()
            Qt.callLater(tabSlot.showNextPermission)
        }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        background: Rectangle {
            radius: 16
            color: Theme.bg
            border.color: Theme.border
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: (tabSlot.pendingPermission ? tabSlot.pendingPermission.origin.host : "") + " " + tabSlot.pendingPermissionLabel + "?"
                textFormat: Text.PlainText
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