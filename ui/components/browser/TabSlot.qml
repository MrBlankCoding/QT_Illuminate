import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// one per tab: the internal page or the web view (+ devtools)
Item {
    id: tabSlot
    property var browserContext: Browser
    required property int index
    required property var model
    required property var browserWindow
    required property var viewStack
    readonly property var splitMemberIds: {
        if (!browserContext)
            return [];
        const revision = browserContext.sidebar.structureRevision;
        return revision >= 0 ? browserContext.sidebar.splitTabs(model.id) : [];
    }
    readonly property int splitMemberIndex: splitMemberIds ? splitMemberIds.indexOf(model.id) : -1
    readonly property real splitGap: splitMemberIndex >= 0 ? 8 : 0
    x: splitMemberIndex === 1 ? parent.width / 2 + splitGap / 2 : 0
    width: splitMemberIndex < 0 ? parent.width
        : parent.width / 2 - splitGap / 2
    height: parent.height
    visible: index === (browserContext ? browserContext.tabModel.activeIndex : -1) || splitMemberIndex >= 0

    function refreshNativeView() {
        if (!tabSlot.webView || !tabSlot.visible || !tabSlot.browserContext)
            return;
        const shouldRaise = tabSlot.index === tabSlot.browserContext.tabModel.activeIndex;
        tabSlot.webView.refreshNativeView(shouldRaise);
    }

    onSplitMemberIndexChanged: {
        Qt.callLater(tabSlot.refreshNativeView);
    }

    TapHandler {
        enabled: tabSlot.splitMemberIndex >= 0
        onTapped: if (tabSlot.browserContext)
            tabSlot.browserContext.activateTab(tabSlot.index)
    }

    Connections {
        target: tabSlot.browserContext ? tabSlot.browserContext.tabModel : null
        function onActiveIndexChanged() {
            if (tabSlot.splitMemberIndex >= 0 || tabSlot.index === tabSlot.browserContext.tabModel.activeIndex)
                Qt.callLater(tabSlot.refreshNativeView);
        }
    }

    readonly property bool isInternalPage: InternalPages.isInternal(model.url.toString())
    readonly property string tabUrl: model.url.toString()
    onIsInternalPageChanged: if (isInternalPage && browserContext) browserContext.updateTabRenderProcessPid(model.id, 0)

    function syncBundledIcon() {
        if (!tabSlot.browserContext)
            return;
        const icon = InternalPages.iconUrl(tabSlot.tabUrl);
        const existingIcon = String(tabSlot.model.iconUrl || "");
        if (icon !== "" || existingIcon.startsWith("qrc:/QT_Illuminate/ui/icons/"))
            tabSlot.browserContext.updateTabIcon(tabSlot.model.id, icon);
    }
    onTabUrlChanged: syncBundledIcon()
    Component.onCompleted: syncBundledIcon()
    function syncRenderPid() {
        if (browserContext)
            browserContext.updateTabRenderProcessPid(tabSlot.webView ? tabSlot.webView["ownerTabId"] : tabSlot.model.id, // qmllint disable missing-property
                                                     tabSlot.webView ? tabSlot.webView.renderProcessPid : 0)
    }

    readonly property int discardAfterMs: Prefs.autoUnloadEnabled
        ? Math.max(1, Prefs.autoUnloadMinutes) * 60 * 1000
        : 0
    property bool discardable: false
    onVisibleChanged: if (visible) discardable = false
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

    Loader {
        anchors.fill: parent
        active: tabSlot.isInternalPage
        visible: tabSlot.isInternalPage
        source: tabSlot.isInternalPage ? InternalPages.qmlSource(tabSlot.model.url.toString()) : ""
        onLoaded: {
            if (tabSlot.browserContext)
                tabSlot.browserContext.updateTabTitle(tabSlot.model.id, InternalPages.title(tabSlot.model.url.toString()));
            tabSlot.syncBundledIcon();
        }
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
            {
                const currentTab = tabSlot.browserContext ? tabSlot.browserContext.tabModel.tabAt(tabSlot.index) : null;
                if (currentTab && currentTab.id === tabSlot.model.id) {
                    item.ownerTabId = currentTab.id;
                    item.url = u;
                }
            }
        }

        sourceComponent: Component {
            CefBrowser {
                id: webView
                property string ownerTabId: ""
                anchors.fill: parent
                visible: tabSlot.visible
                inputSuppressed: tabSlot.browserWindow.inputOverlayOpen
                    && tabSlot.index === (tabSlot.browserContext ? tabSlot.browserContext.tabModel.activeIndex : -1)
                lifecycleState: webView.visible
                    ? CefBrowser.Active
                    : (tabSlot.discardable ? CefBrowser.Discarded : CefBrowser.Frozen)
                onLifecycleStateChanged: tabSlot.syncRenderPid()
                onNativeFocusRequested: tabSlot.browserWindow.returnFocusToWeb()
                backgroundColor: Theme.bg
                cornerRadius: tabSlot.viewStack.cornerRadius
                Component.onCompleted: {
                    ownerTabId = tabSlot.model.id;
                    Logger.debug("WebView", "Tab " + tabSlot.index + " created");
                    const browserTab = tabSlot.browserContext ? tabSlot.browserContext.tabModel.tabAt(tabSlot.index) : null;
                    if (browserTab && browserTab.id === ownerTabId) {
                        browserTab.setCefBrowserWrapper(webView);
                    }
                }

                onLoadingChanged: function () {
                    if (tabSlot.browserContext)
                        tabSlot.browserContext.updateTabLoading(webView.ownerTabId, webView.loading);
                    tabSlot.syncRenderPid();
                    if (webView.loading)
                        Logger.debug("WebView", "Tab " + tabSlot.index + " loading");
                }

                onJavaScriptConsoleMessage: function (level, message, lineNumber, sourceId) {
                    const msg = String(message)
                    if (level === 0)
                        return
                    const text = level + "/" + sourceId + ":" + lineNumber + " " + msg
                    if (level >= 3)
                        Logger.error("WebView", text)
                    else
                        Logger.warning("WebView", text)
                }

                onUrlChanged: function () {
                    if (tabSlot.browserContext)
                        tabSlot.browserContext.updateTabUrl(webView.ownerTabId, webView.url.toString());
                }

                onLoadProgressChanged: function (p) { if (tabSlot.browserContext) tabSlot.browserContext.updateTabProgress(webView.ownerTabId, p) }
                onRenderProcessPidChanged: tabSlot.syncRenderPid()
                onTitleChanged: if (tabSlot.browserContext) tabSlot.browserContext.updateTabTitle(webView.ownerTabId, webView.title)
                onIconChanged: if (tabSlot.browserContext) tabSlot.browserContext.updateTabIcon(webView.ownerTabId, webView.icon.toString())

                onNewWindowRequested: function (url) {
                    if (tabSlot.browserContext)
                        tabSlot.browserContext.openTabFrom(webView.ownerTabId, url.toString());
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
                    target: tabSlot.browserContext
                    function onLoadRequested(tabId, url) {
                        if (tabId !== webView.ownerTabId)
                            return;
                        if (webLoader.item)
                            webLoader.item.url = url;
                    }
                    function onNavigationRequested(tabId, action) {
                        if (tabId !== webView.ownerTabId)
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
