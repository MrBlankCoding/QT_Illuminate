import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Window {
    id: root
    width: 1280
    height: 840
    minimumWidth: 640
    minimumHeight: 420
    title: (Browser.activeTitle || "New Tab") + " — QT_Illuminate"
    color: Theme.bg
    // no native title bar on Windows/Linux: the tab bar draws the window controls
    readonly property bool frameless: Qt.platform.os !== "osx"
    flags: frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window

    function switchProfile(profile) {
        if (!profile)
            return;
        ProfileManager.activeProfile = profile;
        const wv = viewStack.activeWebView;
        if (wv && wv.url.toString() !== "")
            wv.reload();
    }

    // one settings window per browser window, created on first use
    property Window settingsWindow: null

    function openSettings() {
        if (!settingsWindow) {
            const component = Qt.createComponent("qrc:/QT_Illuminate/ui/ui/pages/SettingsWindow.qml");
            if (component.status !== Component.Ready) {
                Logger.error("BrowserWindow", "Settings window failed to load: " + component.errorString());
                return;
            }
            settingsWindow = component.createObject(root) as Window;
            if (!settingsWindow)
                return;
        }
        settingsWindow.show();
        settingsWindow.raise();
        settingsWindow.requestActivate();
    }

    function openProfileSelector() {
        const component = Qt.createComponent("qrc:/QT_Illuminate/ui/ui/pages/ProfilePicker.qml");
        if (component.status !== Component.Ready)
            return;
        const picker = component.createObject(null) as Window;
        if (!picker)
            return;
        picker.show();
        root.close();
    }

    Component.onCompleted: {
        Logger.info("BrowserWindow", "Window ready, platform=" + Qt.platform.os);
        WindowHelper.applyTitleBarStyle(root, Theme.tabBarHeight);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // tab strip
        TabBar {
            id: tabBar
            Layout.fillWidth: true
        }

        // toolbar
        Toolbar {
            id: toolbar
            Layout.fillWidth: true
            z: 100

            currentUrl: Browser.activeUrl === "newtab://newtab" ? "" : Browser.activeUrl
            currentTitle: Browser.activeTitle
            currentIconUrl: Browser.tabModel.activeIndex >= 0 ? Browser.tabModel.itemAt(Browser.tabModel.activeIndex).iconUrl : ""
            isLoading: Browser.activeLoading
            loadProgress: Browser.activeProgress
            canGoBack: viewStack.activeWebView ? viewStack.activeWebView.canGoBack : false
            canGoForward: viewStack.activeWebView ? viewStack.activeWebView.canGoForward : false
            findBar: findBar
            zoomIndicator: zoomIndicator
            downloadsPanel: downloadsPanel

            onNavigate: function (input) {
                Browser.navigate(input);
            }
            onSwitchToProfile: profile => root.switchProfile(profile)
            onOpenProfileSelector: root.openProfileSelector()
            onOpenSettings: root.openSettings()
        }

        // content area
        Item {
            id: viewStack
            Layout.fillWidth: true
            Layout.fillHeight: true

            // tracks the active tab's page. itemAt() isn't reactive on its
            // own, but TabSlot.webView is bound to the loader's item, so the
            // binding re-fires when the page loads or the tab switches.
            readonly property WebEngineView activeWebView: (viewRepeater.itemAt(Browser.tabModel.activeIndex) as TabSlot)?.webView ?? null

            FindBar {
                id: findBar
                webView: viewStack.activeWebView
            }

            ZoomIndicator {
                id: zoomIndicator
                webView: viewStack.activeWebView
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 16
            }

            DownloadsPanel {
                id: downloadsPanel
            }

            Connections {
                target: Browser
                function onActiveIndexChanged() {
                    findBar.close();
                }
                function onNewTabOpened() {
                    // defer so the new tab's view doesn't steal focus back
                    Qt.callLater(toolbar.focusAddressBar);
                }
            }

            Repeater {
                id: viewRepeater
                model: Browser.tabModel

                delegate: TabSlot {}
            }
        }
    }

    // frameless windows lose the native resize border
    ResizeGrips {
        anchors.fill: parent
        visible: root.frameless && root.visibility === Window.Windowed
        z: 1000
        onRequestSystemResize: edges => root.startSystemResize(edges)
    }

    KeyboardShortcuts {
        id: keyboardShortcuts
        toolbar: toolbar
        findBar: findBar
        zoomIndicator: zoomIndicator
        downloadsPanel: downloadsPanel
        onSettingsRequested: root.openSettings()
    }

    // one per tab: the internal page or the web view (+ devtools)
    component TabSlot: Item {
        id: tabSlot
        required property int index
        required property var model
        anchors.fill: parent
        visible: index === Browser.tabModel.activeIndex

        readonly property bool isInternalPage: InternalPages.isInternal(model.url.toString())
        property bool devToolsOpen: false
        readonly property WebEngineView webView: webLoader.item as WebEngineView
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

        // console.debug() prefixes used by the frame-bridge user script
        readonly property string frameOriginMarker: "__illuminate_frame_origin__ "
        readonly property string pointerLockMarker: "__illuminate_pointer_lock__ "
        property bool pointerLocked: false
        onPointerLockedChanged: {
            if (pointerLocked)
                pointerLockHint.flash()
            else
                pointerLockHint.opacity = 0
        }

        Loader {
            anchors.fill: parent
            active: tabSlot.isInternalPage
            visible: tabSlot.isInternalPage
            source: tabSlot.isInternalPage ? InternalPages.qmlSource(tabSlot.model.url.toString()) : ""
        }

        Loader {
            id: webLoader
            x: tabSlot.devToolsOpen && tabSlot.devToolsDock === "left" ? tabSlot.clampedDevToolsSize : 0
            y: 0
            width: tabSlot.devToolsOpen && !tabSlot.devToolsVertical ? parent.width - tabSlot.clampedDevToolsSize : parent.width
            height: tabSlot.devToolsOpen && tabSlot.devToolsVertical ? parent.height - tabSlot.clampedDevToolsSize : parent.height
            active: !tabSlot.isInternalPage
            visible: !tabSlot.isInternalPage

            onLoaded: {
                const u = tabSlot.model.url;
                if (u && u.toString() !== "" && !tabSlot.isInternalPage)
                    item.url = u;
            }

            sourceComponent: Component {
                WebEngineView {
                    id: webView
                    anchors.fill: parent

                    // set once at creation; a profile switch replaces every tab
                    profile: Browser.webProfile
                    devToolsView: tabSlot.devToolsOpen ? devToolsLoader.item as WebEngineView : null
                    visible: tabSlot.index === Browser.tabModel.activeIndex

                    lifecycleState: webView.visible
                        ? WebEngineView.LifecycleState.Active
                        : (webView.recommendedState === WebEngineView.LifecycleState.Discarded
                            ? WebEngineView.LifecycleState.Frozen
                            : webView.recommendedState)

                    // avoids a white flash before the first paint
                    backgroundColor: Theme.bg

                    // gpu shit
                    userScripts.collection: [{
                        name: "hide-webgpu",
                        injectionPoint: WebEngineScript.DocumentCreation,
                        worldId: WebEngineScript.MainWorld,
                        runsOnSubFrames: true,
                        sourceCode: "delete Navigator.prototype.gpu;"
                    }, {
                        // pointer lock grant
                        name: "frame-bridge",
                        injectionPoint: WebEngineScript.DocumentCreation,
                        worldId: WebEngineScript.ApplicationWorld,
                        runsOnSubFrames: true,
                        sourceCode: "if (location.origin !== 'null') console.debug('" + tabSlot.frameOriginMarker + "' + location.origin);"
                            + "document.addEventListener('pointerlockchange', () => console.debug('"
                            + tabSlot.pointerLockMarker + "' + (document.pointerLockElement ? 1 : 0)));"
                    }].concat(AdBlocker.cosmeticScript === "" ? [] : [{
                        name: "adblock-cosmetic",
                        injectionPoint: WebEngineScript.DocumentCreation,
                        worldId: WebEngineScript.ApplicationWorld,
                        runsOnSubFrames: true,
                        sourceCode: AdBlocker.cosmeticScript
                    }])

                    settings.dnsPrefetchEnabled: true
                    settings.scrollAnimatorEnabled: true

                    onJavaScriptConsoleMessage: (level, message, lineNumber, sourceID) => {
                        const msg = String(message)
                        if (msg.startsWith(tabSlot.frameOriginMarker)) {
                            PointerLock.allow(webView.profile, msg.slice(tabSlot.frameOriginMarker.length))
                            return
                        }
                        if (msg.startsWith(AdBlocker.cosmeticMarker)) {
                            const pageUrl = msg.slice(AdBlocker.cosmeticMarker.length)
                            const host = new URL(pageUrl).hostname
                            webView.runJavaScript("window.__illuminateAdblock && window.__illuminateAdblock.apply("
                                + JSON.stringify(host) + ", " + AdBlocker.cosmeticFor(pageUrl) + ")",
                                WebEngineScript.ApplicationWorld)
                            return
                        }
                        if (msg.startsWith(tabSlot.pointerLockMarker)) {
                            tabSlot.pointerLocked = msg.slice(tabSlot.pointerLockMarker.length) === "1"
                            return
                        }
                        if (level === 0)
                            return;
                        const text = level + "/" + sourceID + ":" + lineNumber + " " + msg
                        if (level >= 2)
                            Logger.error("WebView", text)
                        else
                            Logger.warning("WebView", text)
                    }

                    Component.onCompleted: {
                        Logger.info("WebView", "Tab " + tabSlot.index + " created, url=" + tabSlot.model.url);
                    }

                    onLoadingChanged: function (loading) {
                        Browser.onLoadingChanged(tabSlot.index, webView.loading);
                        if (webView.loading)
                            Logger.info("WebView", "Tab " + tabSlot.index + " loading: " + webView.url);
                    }

                    onUrlChanged: function () {
                        Browser.onUrlChanged(tabSlot.index, webView.url.toString());
                        Logger.debug("WebView", "Tab " + tabSlot.index + " url → " + webView.url);
                    }

                    onLoadProgressChanged: Browser.onLoadProgressChanged(tabSlot.index, webView.loadProgress)
                    onTitleChanged: Browser.onTitleChanged(tabSlot.index, webView.title)
                    onIconChanged: Browser.onIconUrlChanged(tabSlot.index, webView.icon.toString())

                    onNewWindowRequested: function (request) {
                        // not calling request.openIn() leaves the request ignored;
                        // the controller opens the url in a new tab instead
                        Browser.onNewWindowRequested(tabSlot.index, request.requestedUrl.toString());
                    }

                    onContextMenuRequested: function (request) {
                        request.accepted = true;
                        contextMenu.request = request;
                        contextMenu.popup();
                    }

                    ContextMenu {
                        id: contextMenu
                        webView: webView
                        onToggleDevTools: tabSlot.devToolsOpen = !tabSlot.devToolsOpen
                        onInspectElement: {
                            // InspectElement needs devToolsView set, which happens once
                            // the devtools loader has created its view
                            tabSlot.devToolsOpen = true
                            Qt.callLater(() => webView.triggerWebAction(WebEngineView.InspectElement))
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
                WebEngineView {
                    id: devToolsView
                    anchors.fill: parent
                    profile: Browser.webProfile
                    backgroundColor: Theme.bg

                    // the frontend's close (X) button asks its page to close
                    onWindowCloseRequested: tabSlot.devToolsOpen = false
                    userScripts.collection: [{
                        name: "devtools-bridge",
                        injectionPoint: WebEngineScript.DocumentCreation,
                        worldId: WebEngineScript.MainWorld,
                        sourceCode: "(function () {"
                            + "const host = window.DevToolsHost;"
                            + "if (!host || !host.sendMessageToEmbedder) return;"
                            + "const send = host.sendMessageToEmbedder.bind(host);"
                            + "host.sendMessageToEmbedder = function (json) {"
                            + "  try {"
                            + "    const m = JSON.parse(json);"
                            + "    if (m.method === 'setPreference' && m.params && m.params[0] === 'currentDockState')"
                            + "      console.debug('" + tabSlot.devToolsDockMarker + "' + JSON.parse(m.params[1]));"
                            + "  } catch (e) {}"
                            + "  return send(json);"
                            + "};"
                            + "})();"
                    }]

                    onJavaScriptConsoleMessage: (level, message, lineNumber, sourceID) => {
                        const msg = String(message)
                        if (!msg.startsWith(tabSlot.devToolsDockMarker))
                            return
                        const side = msg.slice(tabSlot.devToolsDockMarker.length)
                        // a separate devtools window isn't supported; keep it docked
                        if (side === "left" || side === "bottom" || side === "right")
                            tabSlot.devToolsDock = side
                        else if (side === "undocked")
                            tabSlot.devToolsDock = "right"
                    }
                }
            }
        }

        // drag handle between the page and devtools
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

        // like Chrome: tell the user how to get their cursor back
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
    }
}
