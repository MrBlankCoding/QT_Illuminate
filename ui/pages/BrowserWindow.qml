import QtQuick
import QtQuick.Controls
import QtWebEngine
import QtWebChannel
import QT_Illuminate.ui

Window {
    id: root
    width: 1280
    height: 840
    minimumWidth: 640
    minimumHeight: 420
    title: (browser.activeTitle || "New Tab") + " — QT_Illuminate"
    color: Theme.bg
    flags: Qt.platform.os === "windows" ? Qt.Window | Qt.FramelessWindowHint : Qt.Window

    Loader {
        id: browserWindowLoader
        active: false
        source: "qrc:/QT_Illuminate/ui/ui/pages/BrowserWindow.qml"
    }

    Loader {
        id: profilePickerLoader
        active: false
        source: "qrc:/QT_Illuminate/ui/ui/pages/ProfilePicker.qml"
    }

    function switchProfile(profile) {
        if (!profile)
            return;
        profileManager.activeProfile = profile;
        browserWindowLoader.active = true;
        if (browserWindowLoader.item) {
            browserWindowLoader.item.showMaximized();
        }
        root.close();
    }

    function openProfileSelector() {
        profilePickerLoader.active = true;
        if (profilePickerLoader.item) {
            profilePickerLoader.item.show();
        }
        root.close();
    }

    // Shared WebChannel for all WebEngineViews. Assigning it to a view's
    // `webChannel` makes Qt inject qt.webChannelTransport into that page, so
    // the userscript's qwebchannel.js client can pick up `extensionInstaller`.
    // Shared WebChannel for all WebEngineViews. Assigning it to a view's
    // `webChannel` makes Qt inject qt.webChannelTransport into that page, so
    // the store interceptor userscript can pick up `extensionInstaller`.
    // QtWebChannel module registers this QML element as `WebChannel` (not the
    // C++ class name QQmlWebChannel); see plugins.qmltypes exports.
    WebChannel {
        id: storeWebChannel
        Component.onCompleted: registerObject("extensionInstaller", extensionInstaller)
    }
    Component.onCompleted: {
        logger.info("BrowserWindow", "Window ready, platform=" + Qt.platform.os);
        if (typeof windowHelper !== "undefined" && typeof windowHelper.applyTitleBarStyle === "function")
            windowHelper.applyTitleBarStyle(root, Theme.tabBarHeight);

        // Chrome Web Store interceptor, injected at document creation into
        // every page of the shared profile. Registering on the profile avoids
        // racing per-tab page setup (the webview's page is null at creation).
            // Qt's qwebchannel.js loads first: it exposes window.QWebChannel, which the
            // interceptor below uses. Same world (MainWorld) so they share window.

        // Insertion order = execution order at the same injection point.
        try {
            const scripts = webProfile.userScripts;
            if (!scripts) {
                logger.error("BrowserWindow", "webProfile.userScripts is null — store interceptor NOT registered");
                return;
            }
            const channelScript = WebEngine.script();
            channelScript.name = "qwebchannelClient";
            channelScript.sourceUrl = "qrc:///qtwebchannel/qwebchannel.js";
            channelScript.injectionPoint = WebEngineScript.DocumentCreation;
            channelScript.worldId = WebEngineScript.MainWorld;
            channelScript.runsOnSubFrames = false;
            scripts.insert(channelScript);
            const script = WebEngine.script();
            script.name = "extensionsStoreInterceptor";
            script.sourceUrl = "qrc:/QT_Illuminate/ui/resources/js/extensions_store_intercept.js";
            script.injectionPoint = WebEngineScript.DocumentCreation;
            script.worldId = WebEngineScript.MainWorld;
            script.runsOnSubFrames = false;
            scripts.insert(script);
            logger.info("BrowserWindow", "Registered qwebchannelClient + extensionsStoreInterceptor on default profile");
        } catch (e) {
            logger.error("BrowserWindow", "Failed to register store interceptor: " + e);
        }
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

            currentUrl: browser.activeUrl === "newtab://newtab" ? "" : browser.activeUrl
            currentTitle: browser.activeTitle
            currentIconUrl: tabModel.activeIndex >= 0 ? tabModel.get(tabModel.activeIndex).iconUrl : ""
            isLoading: browser.activeLoading
            loadProgress: browser.activeProgress
            canGoBack: viewStack.activeWebView ? viewStack.activeWebView.canGoBack : false
            canGoForward: viewStack.activeWebView ? viewStack.activeWebView.canGoForward : false
            findBar: findBar
            zoomIndicator: zoomIndicator
            downloadsPanel: downloadsPanel

            onNavigate: function (input) {
                browser.navigate(input);
            }
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
                function onActiveIndexChanged() {
                    findBar.close();
                }
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
                            const u = model.url;
                            if (u && u.toString() !== "" && !tabSlot.isInternalPage)
                                item.url = u;
                        }

                        sourceComponent: Component {
                            WebEngineView {
                                id: webView
                                anchors.fill: parent

                                devToolsView: tabSlot.devToolsOpen ? devToolsLoader.item : null

                                // tied to active state
                                // this could be for later a place to manage memory of hybernate
                                visible: index === tabModel.activeIndex

                                // Bind this view's Qt WebChannel to the shared channel so the
                                // store interceptor userscript can reach extensionInstaller.
                                // MainWorld matches our user script's worldId.
                                webChannel: storeWebChannel
                                webChannelWorld: WebEngineScript.MainWorld

                                // warnings/errors into the app logger. 0=Info,
                                // 1=Warning, 2=Error.
                                onJavaScriptConsoleMessage: (level, message, lineNumber, sourceID) => {
                                    const text = String(message)
                                    const src = String(sourceID)
                                    if (text.indexOf("StoreIntercept") >= 0 || level >= 1) {
                                        const line = level + "/" + sourceID + ":" + lineNumber + " " + text
                                        if (level >= 2)
                                            logger.error("WebStoreJS", line)
                                        else if (level === 1)
                                            logger.warning("WebStoreJS", line)
                                        else
                                            logger.debug("WebStoreJS", line)
                                    }
                                    // Capture extension-page console output (illum-ext://<extid>/…)
                                    if (webView.url.scheme === "illum-ext" && webView.url.host !== "")
                                        extensionLogs.append(webView.url.host, level, text)
                                }

                                Component.onCompleted: {
                                    logger.info("WebView", "Tab " + index + " created, url=" + model.url);
                                }

                                onLoadingChanged: function (loading) {
                                    browser.onLoadingChanged(index, webView.loading);
                                    if (webView.loading)
                                        logger.info("WebView", "Tab " + index + " loading: " + webView.url);
                                }

                                onUrlChanged: function (url) {
                                    browser.onUrlChanged(index, webView.url.toString());
                                    logger.debug("WebView", "Tab " + index + " url → " + webView.url);
                                }

                                onLoadProgressChanged: browser.onLoadProgressChanged(index, webView.loadProgress)
                                onIconChanged: browser.onIconUrlChanged(index, webView.icon.toString())

                                onNewWindowRequested: function (request) {
                                    request.action = WebEngineNewWindowRequest.IgnoreRequest;
                                    browser.onNewWindowRequested(index, request.requestedUrl.toString());
                                }

                                onContextMenuRequested: function (request) {
                                    request.accepted = true;
                                    contextMenu.request = request;
                                    contextMenu.popup();
                                }

                                ContextMenu {
                                    id: contextMenu
                                    webView: webView
                                    request: request
                                    onToggleDevTools: tabSlot.devToolsOpen = !tabSlot.devToolsOpen
                                }

                                Connections {
                                    target: browser
                                    function onLoadRequested(tabIndex, url) {
                                        if (tabIndex !== index)
                                            return;
                                        if (webLoader.item)
                                            webLoader.item.url = url;
                                    }
                                    function onNavigationRequested(action) {
                                        if (index !== tabModel.activeIndex)
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

    KeyboardShortcuts {
        id: keyboardShortcuts
        toolbar: toolbar
        findBar: findBar
        zoomIndicator: zoomIndicator
        downloadsPanel: downloadsPanel
    }
}
