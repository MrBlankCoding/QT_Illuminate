import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// one per tab: the internal page or the web view
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
    readonly property bool activeTabHasWebView: {
        if (!browserContext)
            return false;
        const activeTab = browserContext.tabModel.tabAt(browserContext.tabModel.activeIndex);
        return activeTab && !InternalPages.isInternal(String(activeTab.url));
    }
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

    Connections {
        target: tabSlot.browserContext ? tabSlot.browserContext.tabModel : null
        function onActiveIndexChanged() {
            if (tabSlot.splitMemberIndex >= 0
                    && tabSlot.index === tabSlot.browserContext.tabModel.activeIndex)
                Qt.callLater(tabSlot.refreshNativeView);
        }
    }

    TapHandler {
        enabled: tabSlot.splitMemberIndex >= 0
        onTapped: if (tabSlot.browserContext)
            tabSlot.browserContext.activateTab(tabSlot.index)
    }

    readonly property bool isInternalPage: InternalPages.isInternal(model.url.toString())
    readonly property string tabUrl: model.url.toString()
    onIsInternalPageChanged: {
        if (isInternalPage && browserContext)
            browserContext.updateTabRenderProcessPid(model.id, 0);
        Qt.callLater(syncWebViewUrl);
    }

    function syncBundledIcon() {
        if (!tabSlot.browserContext)
            return;
        const icon = InternalPages.iconUrl(tabSlot.tabUrl);
        const existingIcon = String(tabSlot.model.iconUrl || "");
        if (icon !== "" || existingIcon.startsWith("qrc:/QT_Illuminate/ui/icons/"))
            tabSlot.browserContext.updateTabIcon(tabSlot.model.id, icon);
    }
    function syncWebViewUrl() {
        if (tabSlot.isInternalPage || !webLoader.item)
            return;

        const targetTab = tabSlot.browserContext
            ? tabSlot.browserContext.tabModel.tabAt(tabSlot.index) : null;
        if (!targetTab || String(targetTab.id) !== String(tabSlot.model.id))
            return;

        const targetUrl = tabSlot.model.url;
        if (!targetUrl || targetUrl.toString() === "")
            return;

        webLoader.item.ownerTabId = String(tabSlot.model.id);
        targetTab.setCefBrowserWrapper(webLoader.item);
        if (tabSlot.model.suspended && tabSlot.index !== tabSlot.browserContext.tabModel.activeIndex
            && tabSlot.splitMemberIndex < 0)
            return;
        if (webLoader.item.url.toString() !== targetUrl.toString())
            webLoader.item.url = targetUrl;
    }

    onTabUrlChanged: {
        syncBundledIcon();
        Qt.callLater(syncWebViewUrl);
    }
    onModelChanged: Qt.callLater(syncWebViewUrl)
    Component.onCompleted: syncBundledIcon()
    function syncRenderPid() {
        if (browserContext)
            browserContext.updateTabRenderProcessPid(tabSlot.webView ? tabSlot.webView["ownerTabId"] : tabSlot.model.id, // qmllint disable missing-property
                                                     tabSlot.webView ? tabSlot.webView.renderProcessPid : 0)
    }

    readonly property CefBrowser webView: webLoader.item as CefBrowser
    onWebViewChanged: {
        Qt.callLater(tabSlot.syncWebViewUrl)
        Qt.callLater(tabSlot.refreshNativeView)
        viewStack.refreshActiveWebView()
    }

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
        anchors.fill: parent
        active: !tabSlot.isInternalPage && (!tabSlot.model.suspended || tabSlot.splitMemberIndex >= 0)
        visible: !tabSlot.isInternalPage

        onLoaded: {
            tabSlot.syncWebViewUrl();
        }

        sourceComponent: Component {
            CefBrowser {
                id: webView
                property string ownerTabId: ""
                profile: tabSlot.browserContext ? tabSlot.browserContext.webProfile : null
                anchors.fill: parent
                visible: tabSlot.visible
                keepVisibleWhileLoading: !tabSlot.visible && webView.loading && tabSlot.activeTabHasWebView
                inputSuppressed: tabSlot.browserWindow.inputOverlayOpen
                    && tabSlot.index === (tabSlot.browserContext ? tabSlot.browserContext.tabModel.activeIndex : -1)
                lifecycleState: webView.visible
                    ? CefBrowser.Active
                    : CefBrowser.Frozen
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
                    else if (tabSlot.visible)
                        // A tab can finish navigation while its native CEF
                        // child window is being hidden or restored. Re-raise
                        // it after the load transition settles so an older
                        // sibling surface cannot remain over the page.
                        Qt.callLater(tabSlot.refreshNativeView);
                }

                onJavaScriptConsoleMessage: function (level, message, lineNumber, sourceId) {
                    const msg = String(message)
                    if (level === 0)
                        return
                    const text = level + "/" + sourceId + ":" + lineNumber + " " + msg
                    if (msg.indexOf("Error with Permissions-Policy header: Unrecognized feature:") >= 0) {
                        Logger.warning("WebConsole", text)
                        return
                    }
                    // the page's own errors surfacing through code an extension
                    // injected (an ad blocker wrapping fetch, say): not ours
                    if (String(sourceId).startsWith("chrome-extension://")) {
                        Logger.debug("ExtensionConsole", text)
                        return
                    }
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
                    permissionPrompt.handlePermission(permission)
                }

                WebContextMenu {
                    id: contextMenu
                    webView: webView
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
                    }
                }

                Connections {
                    target: webView
                    function onLoadRequested(url) {
                        if (!tabSlot.browserContext || !webView.ownerTabId)
                            return;
                        const destination = url.toString();
                        tabSlot.browserContext.updateTabUrl(webView.ownerTabId, destination);
                        tabSlot.browserContext.updateTabTitle(webView.ownerTabId,
                            InternalPages.title(destination) || "New Tab");
                        tabSlot.browserContext.updateTabLoading(webView.ownerTabId, false);
                        tabSlot.browserContext.updateTabProgress(webView.ownerTabId, 0);
                        tabSlot.browserContext.updateTabRenderProcessPid(webView.ownerTabId, 0);
                    }
                }
            }
        }
    }

    PermissionPrompt {
        id: permissionPrompt
        anchors.fill: parent
        tabSlot: tabSlot
    }

}
