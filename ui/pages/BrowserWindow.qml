import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtWebEngine
import QT_Illuminate.ui


Window {
    id: root
    width: 1280
    height: 840
    minimumWidth: 640
    minimumHeight: 420
    title: (browser.activeTitle || "New Tab") + " — QT_Illuminate"
    color: Theme.bg
    flags: Qt.platform.os === "windows"
        ? Qt.Window | Qt.FramelessWindowHint
        : Qt.Window

    function switchProfile(profile) {
        if (!profile) return
        profileManager.activeProfile = profile
        var comp = Qt.createComponent("qrc:/QT_Illuminate/ui/ui/pages/BrowserWindow.qml")
        var win = comp.createObject(null)
        win.showMaximized()
        root.close()
    }

    function openProfileSelector() {
        var comp = Qt.createComponent("qrc:/QT_Illuminate/ui/ui/pages/ProfilePicker.qml")
        var win = comp.createObject(null)
        win.show()
        root.close()
    }

    Component.onCompleted: {
        logger.info("BrowserWindow", "Window ready, platform=" + Qt.platform.os)
        if (typeof windowHelper !== "undefined" && typeof windowHelper.applyTitleBarStyle === "function")
            windowHelper.applyTitleBarStyle(root, Theme.tabBarHeight)
    }

    Column {
        anchors.fill: parent

        // tab strip
        TabBar {
            id: tabBar
            width: parent.width
        }

        // toolbar
        Toolbar {
            id: toolbar
            width: parent.width
            z: 100

            currentUrl:   browser.activeUrl === "newtab://newtab" ? "" : browser.activeUrl
            currentTitle: browser.activeTitle
            currentIconUrl: tabModel.activeIndex >= 0 ? tabModel.get(tabModel.activeIndex).iconUrl : ""
            isLoading: browser.activeLoading
            loadProgress: browser.activeProgress
            canGoBack:    viewStack.activeWebView ? viewStack.activeWebView.canGoBack    : false
            canGoForward: viewStack.activeWebView ? viewStack.activeWebView.canGoForward : false
            findBar:      findBar
            zoomIndicator: zoomIndicator
            downloadsPanel: downloadsPanel

            onNavigate: function(input) { browser.navigate(input) }
            onSwitchToProfile: root.switchProfile(profile)
            onOpenProfileSelector: root.openProfileSelector()
        }

        // content area
        Item {
            id: viewStack
            width: parent.width
            height: root.height - tabBar.height - toolbar.height

            // sync by each tab's Binding below — itemAt() on the
            // Repeater isn't itself a reactive property, so pushing the
            // value from the active delegate is what keeps FindBar's
            // webView from going stale when a tab loads or switches.
            property var activeWebView: null

            FindBar {
                id: findBar
                webView: viewStack.activeWebView
            }

            ZoomIndicator {
                id: zoomIndicator
                webView: viewStack.activeWebView
            }

            DownloadsPanel {
                id: downloadsPanel
            }

            Connections {
                target: browser
                function onActiveIndexChanged() { findBar.close() }
            }

            Repeater {
                id: viewRepeater
                model: tabModel

                Item {
                    id: tabSlot
                    anchors.fill: parent
                    visible: index === tabModel.activeIndex

                    readonly property bool isInternalPage: internalPages.isInternal(model.url.toString())
                    property bool devToolsOpen: false
                    property alias webView: webLoader.item

                    Binding {
                        target: viewStack
                        property: "activeWebView"
                        value: tabSlot.webView
                        when: tabSlot.visible
                    }

                    Loader {
                        anchors.fill: parent
                        active: tabSlot.isInternalPage
                        visible: tabSlot.isInternalPage
                        source: tabSlot.isInternalPage ? internalPages.qmlSource(model.url.toString()) : ""
                    }

                    Loader {
                        id: webLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: tabSlot.devToolsOpen ? parent.height * 0.65 : parent.height
                        active: !tabSlot.isInternalPage
                        visible: !tabSlot.isInternalPage

                        onLoaded: {
                            const u = model.url
                            if (u && u.toString() !== "" && !tabSlot.isInternalPage)
                                item.url = u
                        }

                            sourceComponent: Component {
                                WebEngineView {
                                    id: webView
                                    anchors.fill: parent

                                    devToolsView: tabSlot.devToolsOpen ? devToolsLoader.item : null

                                    // tied to active state 
                                    // this could be for later a place to manage memory of tabs and hybernate
                                    visible: index === tabModel.activeIndex

                                    Component.onCompleted: {
                                        logger.info("WebView", "Tab " + index + " created, url=" + model.url)
                                    }

                                    onTitleChanged: browser.onTitleChanged(index, webView.title)
                                    onUrlChanged: {
                                        browser.onUrlChanged(index, webView.url.toString())
                                        logger.debug("WebView", "Tab " + index + " url → " + webView.url)
                                    }
                                    onLoadingChanged: {
                                        browser.onLoadingChanged(index, webView.loading)
                                        if (webView.loading)
                                            logger.info("WebView", "Tab " + index + " loading: " + webView.url)
                                    }
                                    onLoadProgressChanged: browser.onLoadProgressChanged(index, webView.loadProgress)
                                    onIconChanged: browser.onIconUrlChanged(index, webView.icon.toString())

                                    onNewWindowRequested: function(request) {
                                    request.action = WebEngineNewWindowRequest.IgnoreRequest
                                    browser.onNewWindowRequested(index, request.requestedUrl.toString())
                                }

                                onContextMenuRequested: function(request) {
                                    request.accepted = true
                                    contextMenu.request = request
                                    contextMenu.popup()
                                }

                                // native context menu
                                Menu {
                                    id: contextMenu
                                    popupType: Popup.Native

                                    property var request: null

                                    MenuItem {
                                        text: "Back"
                                        enabled: webView.canGoBack
                                        onTriggered: webView.goBack()
                                    }
                                    MenuItem {
                                        text: "Forward"
                                        enabled: webView.canGoForward
                                        onTriggered: webView.goForward()
                                    }
                                    MenuItem {
                                        text: "Reload"
                                        onTriggered: webView.reload()
                                    }
                                    MenuSeparator {}
                                    MenuItem {
                                        text: "Copy Link"
                                        visible: contextMenu.request && contextMenu.request.linkUrl.toString() !== ""
                                        onTriggered: webView.triggerWebAction(WebEngineView.CopyLinkToClipboard)
                                    }
                                    MenuItem {
                                        // rename based on what was clicked
                                        // this allows for downloads to be specific
                                        // download image etc
                                        readonly property int mediaType: contextMenu.request ? contextMenu.request.mediaType : ContextMenuRequest.MediaTypeNone
                                        readonly property bool hasLink: contextMenu.request && contextMenu.request.linkUrl.toString() !== ""

                                        text: mediaType === ContextMenuRequest.MediaTypeImage ? "Download Image"
                                            : mediaType === ContextMenuRequest.MediaTypeVideo ? "Download Video"
                                            : mediaType === ContextMenuRequest.MediaTypeAudio ? "Download Audio"
                                            : "Download Link"
                                        visible: mediaType === ContextMenuRequest.MediaTypeImage
                                                 || mediaType === ContextMenuRequest.MediaTypeVideo
                                                 || mediaType === ContextMenuRequest.MediaTypeAudio
                                                 || hasLink
                                        onTriggered: {
                                            if (mediaType === ContextMenuRequest.MediaTypeImage)
                                                webView.triggerWebAction(WebEngineView.DownloadImageToDisk)
                                            else if (mediaType === ContextMenuRequest.MediaTypeVideo || mediaType === ContextMenuRequest.MediaTypeAudio)
                                                webView.triggerWebAction(WebEngineView.DownloadMediaToDisk)
                                            else
                                                webView.triggerWebAction(WebEngineView.DownloadLinkToDisk)
                                        }
                                    }
                                    MenuItem {
                                        text: "Copy"
                                        visible: contextMenu.request && contextMenu.request.selectedText !== ""
                                        onTriggered: webView.triggerWebAction(WebEngineView.Copy)
                                    }
                                    MenuItem {
                                        text: "Paste"
                                        visible: contextMenu.request && contextMenu.request.isContentEditable
                                        onTriggered: webView.triggerWebAction(WebEngineView.Paste)
                                    }
                                    MenuSeparator {}
                                    MenuItem {
                                        text: "Toggle Dev Tools"
                                        onTriggered: tabSlot.devToolsOpen = !tabSlot.devToolsOpen
                                    }
                                }

                                Connections {
                                    target: browser
                                    function onLoadRequested(tabIndex, url)
                                    {
                                        if (tabIndex !== index) return
                                        if (webLoader.item) webLoader.item.url = url
                                    }
                                    function onNavigationRequested(action)
                                    {
                                        if (index !== tabModel.activeIndex) return
                                        if (action === "back") webView.goBack()
                                            else if (action === "forward") webView.goForward()
                                        else if (action === "reload") webView.reload()
                                        else if (action === "devtools") tabSlot.devToolsOpen = !tabSlot.devToolsOpen
                                        }
                                    }
                                }
                            }
                        }

                        Loader {
                            id: devToolsLoader
                            anchors.top: webLoader.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            active: tabSlot.devToolsOpen
                            visible: tabSlot.devToolsOpen

                            sourceComponent: Component {
                                WebEngineView {
                                    anchors.fill: parent
                                }
                            }
                        }
                    }
                }
            }
        }

        // only used on frameless platforms
        property int edgeGrip: 6
        property int cornerGrip: 10

                Item {
                    id: resizeGrips
                    anchors.fill: parent
                    visible: false
                    enabled: visible

                    MouseArea { // left
                        height: root.height - root.cornerGrip * 2
                        width: root.edgeGrip
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        cursorShape: Qt.SizeHorCursor
                        onPressed: root.startSystemResize(Qt.LeftEdge)
                    }
                    MouseArea { // right
                        height: root.height - root.cornerGrip * 2
                        width: root.edgeGrip
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        cursorShape: Qt.SizeHorCursor
                        onPressed: root.startSystemResize(Qt.RightEdge)
                    }
                    MouseArea { // bottom
                        width: root.width - root.cornerGrip * 2
                        height: root.edgeGrip
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        cursorShape: Qt.SizeVerCursor
                        onPressed: root.startSystemResize(Qt.BottomEdge)
                    }
                    MouseArea { // top-left corner
                        width: root.cornerGrip; height: root.cornerGrip
                        anchors.top: parent.top; anchors.left: parent.left
                        cursorShape: Qt.SizeFDiagCursor
                        onPressed: root.startSystemResize(Qt.TopEdge | Qt.LeftEdge)
                    }
                    MouseArea { // top-right corner
                        width: root.cornerGrip; height: root.cornerGrip
                        anchors.top: parent.top; anchors.right: parent.right
                        cursorShape: Qt.SizeBDiagCursor
                        onPressed: root.startSystemResize(Qt.TopEdge | Qt.RightEdge)
                    }
                    MouseArea { // bottom-left corner
                        width: root.cornerGrip; height: root.cornerGrip
                        anchors.bottom: parent.bottom; anchors.left: parent.left
                        cursorShape: Qt.SizeBDiagCursor
                        onPressed: root.startSystemResize(Qt.BottomEdge | Qt.LeftEdge)
                    }
                    MouseArea { // bottom-right corner
                        width: root.cornerGrip; height: root.cornerGrip
                        anchors.bottom: parent.bottom; anchors.right: parent.right
                        cursorShape: Qt.SizeFDiagCursor
                        onPressed: root.startSystemResize(Qt.BottomEdge | Qt.RightEdge)
                    }
                }

                // this should be somewhere else
                // but for now it can live here
                KeyboardShortcuts {
                    toolbar: toolbar
                    findBar: findBar
                    zoomIndicator: zoomIndicator
                    downloadsPanel: downloadsPanel
                }
            }
