import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Window {
    id: root
    width: 1280
    height: 840
    minimumWidth: 640
    minimumHeight: 420
    title: (Browser.activeTitle || "New Tab") + " — QT_Illuminate"
    color: Theme.sidebarBg
    readonly property bool frameless: Qt.platform.os !== "osx"
    flags: frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window
    readonly property bool contentFullScreen: viewStack.activeWebView ? viewStack.activeWebView.fullScreen : false
    property bool fullScreenForContent: false
    property bool contentFullScreenShown: false
    property int visibilityBeforeContentFullScreen: Window.Windowed
    property int visibilityBeforeWindowFullScreen: Window.Windowed
    property bool findBarOpen: false
    readonly property bool inputOverlayOpen: commandBar.visible || root.findBarOpen
    function toggleFullScreen() {
        if (root.visibility === Window.FullScreen) {
            if (root.visibilityBeforeWindowFullScreen === Window.Maximized)
                root.showMaximized();
            else
                root.showNormal();
            return;
        }
        root.showFullScreen();
    }

    onContentFullScreenChanged: {
        // views torn down on the way out must not re-show the window
        if (root.retiring)
            return;
        if (contentFullScreen) {
            if (root.visibility !== Window.FullScreen) {
                root.visibilityBeforeContentFullScreen = root.visibility;
                root.fullScreenForContent = true;
                root.showFullScreen();
            }
        } else if (root.fullScreenForContent) {
            root.fullScreenForContent = false;
            root.contentFullScreenShown = false;
            if (root.visibilityBeforeContentFullScreen === Window.Maximized)
                root.showMaximized();
            else
                root.showNormal();
        }
    }

    onVisibilityChanged: {
        if (root.visibility !== Window.FullScreen)
            root.visibilityBeforeWindowFullScreen = root.visibility;

        if (!root.contentFullScreen)
            return;
        if (root.visibility === Window.FullScreen)
            root.contentFullScreenShown = true;
        else if (root.contentFullScreenShown && viewStack.activeWebView)
            // user left macOS fullscreen (green button, Ctrl+Cmd+F): end the page's too
            viewStack.activeWebView.exitFullScreen();
    }

    function switchProfile(profile) {
        if (!profile)
            return;
        const component = Qt.createComponent("qrc:/QT_Illuminate/ui/ui/pages/BrowserWindow.qml");
        if (component.status !== Component.Ready) {
            Logger.error("BrowserWindow", "Failed to load window for profile switch: " + component.errorString());
            return;
        }
        root.retiring = true;
        ProfileManager.activeProfile = profile;
        const w = component.createObject(null) as Window;
        if (!w) {
            root.retiring = false;
            return;
        }
        Browser.adoptWindow(w);
        w.show();
        root.retire();
    }

    // closing (with skipCloseConfirm set) releases the window in onClosing
    function retire() {
        root.retiring = true
        root.skipCloseConfirm = true
        root.replacedByNewWindow = true
        root.close();
    }

    property Window settingsWindow: null
    property bool skipCloseConfirm: false
    property bool replacedByNewWindow: false
    // set while this window is being replaced: its tab views are torn down
    property bool retiring: false
    signal windowClosed

    function requestWindowClose() {
        if (Browser.confirmCloseRequired()) {
            closeDialog.open()
            return
        }
        root.skipCloseConfirm = true
        root.close()
    }

    onClosing: function(close) {
        if (root.skipCloseConfirm || !Browser.confirmCloseRequired()) {
            // A window that is merely being replaced is not the user closing the
            // browser, so the profile picker waiting on windowClosed must not
            // bring itself back on top of the replacement.
            if (!root.replacedByNewWindow)
                root.windowClosed()
            // a closed window is never shown again; left alive it would keep
            // creating views for the shared tab model and reacting to menus
            Browser.releaseWindow(root)
            return;
        }
        close.accepted = false
        closeDialog.open()
    }

    readonly property bool sidebarCollapsed: Prefs.sidebarCollapsed
    property bool sidebarPeeked: false
    property bool sidebarPeekSuppressed: false
    onSidebarPeekedChanged: {
        if (Theme.isMac)
            WindowHelper.setWindowButtonsVisible(root, !root.sidebarCollapsed || root.sidebarPeeked);
    }
    onSidebarCollapsedChanged: {
        if (Theme.isMac)
            WindowHelper.setWindowButtonsVisible(root, !root.sidebarCollapsed || root.sidebarPeeked);
        if (!root.sidebarCollapsed) {
            root.sidebarPeeked = false;
            root.sidebarPeekSuppressed = false;
            sidebarOverlay.close();
        } else {
            root.sidebarPeeked = false;
            root.sidebarPeekSuppressed = true;
        }
    }

    function toggleSidebar() {
        Prefs.sidebarCollapsed = !Prefs.sidebarCollapsed;
    }

    function openCommandBar(mode) {
        sidebarOverlay.close();
        const url = Browser.activeUrl;
        if (mode === "edit" && url !== "" && url !== "newtab://newtab")
            commandBar.openEdit(url);
        else
            commandBar.openNew();
    }

    function toggleBookmark() {
        const url = Browser.activeUrl;
        if (url === "" || url === "newtab://newtab")
            return;
        Bookmarks.toggleBookmark(Browser.activeTitle, url, Browser.activeIconUrl);
    }

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
        Browser.adoptWindow(picker);
        // before retiring, so the app never has a moment with no window
        picker.show();
        picker.raise();
        picker.requestActivate();
        root.retire();
    }

    Dialog {
        id: closeDialog
        title: "Close window?"
        // own native window: the page's CEF view would cover an in-scene popup
        popupType: Popup.Window
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        modal: true
        width: Math.min(360, root.width - 80)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 10
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
        }

        header: Text {
            text: closeDialog.title
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
            font.weight: Font.Medium
            color: Theme.text
            padding: 16
            bottomPadding: 0
        }

        contentItem: Text {
            text: Browser.tabModel.count > 1
                ? "This window has " + Browser.tabModel.count + " tabs open."
                : "This window has a tab open."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
            color: Theme.textMuted
            wrapMode: Text.WordWrap
        }

        footer: RowLayout {
            spacing: 8

            Item { Layout.fillWidth: true }

            PillButton {
                text: "Cancel"
                fillColor: "transparent"
                textColor: Theme.text
                Layout.topMargin: 12
                Layout.bottomMargin: 16
                onClicked: closeDialog.close()
            }

            PillButton {
                text: "Close window"
                fillColor: Theme.accent
                hoverFillColor: Qt.darker(Theme.accent, 1.1)
                textColor: Theme.onAccent
                Layout.topMargin: 12
                Layout.bottomMargin: 16
                Layout.rightMargin: 16
                onClicked: {
                    closeDialog.close()
                    root.skipCloseConfirm = true
                    root.close()
                }
            }
        }
    }

    Dialog {
        id: aboutDialog
        title: "About " + Qt.application.name
        popupType: Popup.Window
        // Popup isn't an Item, so position it by hand
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        modal: true
        width: Math.min(360, root.width - 80)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 10
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
        }

        header: Text {
            text: aboutDialog.title
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
            font.weight: Font.Medium
            color: Theme.text
            padding: 16
            bottomPadding: 0
        }

        contentItem: ColumnLayout {
            spacing: 6

            Text {
                text: "Version " + (Qt.application.version || "unknown")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                color: Theme.text
                Layout.fillWidth: true
            }

            Text {
                text: "A Qt Quick browser built on the Chromium Embedded Framework."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                color: Theme.textMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        footer: RowLayout {
            spacing: 8

            Item { Layout.fillWidth: true }

            PillButton {
                text: "Close"
                fillColor: Theme.accent
                hoverFillColor: Qt.darker(Theme.accent, 1.1)
                textColor: Theme.onAccent
                Layout.topMargin: 12
                Layout.bottomMargin: 16
                Layout.rightMargin: 16
                onClicked: aboutDialog.close()
            }
        }
    }

    property bool pointerLockActive: false
    property PointerLockEmu pointerLockEmu: PointerLockEmu {}

    PrintController {
        id: printController
        activeWebView: viewStack.activeWebView
    }

    function printActivePage() { printController.printActivePage(); }
    function savePdfActivePage() { printController.savePdfActivePage(); }
    function openSystemPrintFor(view) { printController.openSystemPrintFor(view); }
    function onPdfPrintingFinished(filePath, success) { printController.onPdfPrintingFinished(filePath, success); }

    function releasePointerLock() {
        const tab = viewRepeater.itemAt(Browser.tabModel.activeIndex) as TabSlot;
        if (tab)
            tab.releaseLock();
        pointerLockActive = false;
    }

    Component.onCompleted: {
        Logger.info("BrowserWindow", "Window ready, platform=" + Qt.platform.os);
        WindowHelper.applyTitleBarStyle(root, Theme.titleBarHeight);
        WindowHelper.setWindowButtonsVisible(root, !root.sidebarCollapsed || root.sidebarPeeked);
        AppMenu.attach(root);
    }

    Component.onDestruction: AppMenu.detach(root)

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            id: dock
            Layout.fillHeight: true
            Layout.preferredWidth: (root.sidebarCollapsed && !root.sidebarPeeked) || root.contentFullScreen
                ? 0 : (dockLoader.item ? dockLoader.item.implicitWidth : 0)
            clip: true
            visible: Layout.preferredWidth > 0

            Behavior on Layout.preferredWidth {
                enabled: !dockLoader.item || dockLoader.item.dragWidth < 0
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            HoverHandler {
                id: dockHover
                enabled: Theme.isMac && root.sidebarCollapsed
                onHoveredChanged: {
                    if (hovered)
                        peekHideDelay.stop();
                    else if (root.sidebarPeeked)
                        peekHideDelay.restart();
                }
            }

            Loader {
                id: dockLoader
                width: item ? item.implicitWidth : 0
                height: parent.height
                // kept alive while collapsed so expanding is instant
                sourceComponent: sidebarComponent
            }
        }

        WebContentCard {
            id: card
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: root.contentFullScreen ? 0 : Theme.cardMargin
            radius: root.contentFullScreen ? 0 : Theme.radiusCard
            shadowEnabled: !root.contentFullScreen
            roundContent: InternalPages.isInternal(Browser.activeUrl)

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // content area
                Item {
                    id: viewStack
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    property CefBrowser activeWebView: null
                    readonly property real cornerRadius: card.radius

                    function refreshActiveWebView() {
                        const tab = viewRepeater.itemAt(Browser.tabModel.activeIndex) as TabSlot;
                        const next = tab ? tab.webView : null;
                        if (viewStack.activeWebView && viewStack.activeWebView !== next && viewStack.activeWebView.fullScreen)
                            viewStack.activeWebView.exitFullScreen();
                        viewStack.activeWebView = next;
                    }

                    Component.onCompleted: Qt.callLater(viewStack.refreshActiveWebView)

                    FindBar {
                        id: findBar
                        webView: viewStack.activeWebView
                        onVisibleChanged: root.findBarOpen = visible
                    }

                    ZoomIndicator {
                        id: zoomIndicator
                        webView: viewStack.activeWebView
                    }

                    DownloadsPanel {
                        id: downloadsPanel
                    }

                    Connections {
                        target: Browser
                        enabled: !root.retiring
                        function onActiveIndexChanged() {
                            findBar.close();
                            viewStack.refreshActiveWebView();
                        }
                        function onNewTabOpened() {
                            Qt.callLater(() => root.openCommandBar("new"));
                        }

                        function onCloseWindowRequested() {
                            root.requestWindowClose();
                        }
                    }

                    Repeater {
                        id: viewRepeater
                        model: root.retiring ? null : Browser.tabModel

                        delegate: TabSlot {
                            browserWindow: root
                            viewStack: viewStack
                        }

                        onItemAdded: viewStack.refreshActiveWebView()
                        onItemRemoved: viewStack.refreshActiveWebView()
                    }
                }
            }
        }
    }

    Component {
        id: sidebarComponent

        Sidebar {
            targetWindow: root
            currentUrl: Browser.activeUrl === "newtab://newtab" ? "" : Browser.activeUrl
            currentTitle: Browser.activeTitle
            currentIconUrl: Browser.activeIconUrl
            isLoading: Browser.activeLoading
            loadProgress: Browser.activeProgress
            canGoBack: viewStack.activeWebView ? viewStack.activeWebView.canGoBack : false
            canGoForward: viewStack.activeWebView ? viewStack.activeWebView.canGoForward : false
            findBar: findBar
            zoomIndicator: zoomIndicator
            downloadsPanel: downloadsPanel

            onSwitchToProfile: profile => root.switchProfile(profile)
            onOpenProfileSelector: root.openProfileSelector()
            onOpenSettings: root.openSettings()
            onCommandBarRequested: mode => root.openCommandBar(mode)
            onToggleCollapsed: root.toggleSidebar()
        }
    }

    Item {
        id: revealEdge
        x: 0
        y: 0
        width: Theme.cardMargin + 2
        height: parent.height
        visible: root.sidebarCollapsed && !root.contentFullScreen && (!Theme.isMac || !root.sidebarPeeked)

        HoverHandler {
            id: revealHover
            onHoveredChanged: {
                if (hovered) {
                    if (!root.sidebarPeekSuppressed)
                        revealDelay.restart();
                } else {
                    revealDelay.stop();
                    root.sidebarPeekSuppressed = false;
                }
            }
        }
        Timer {
            id: revealDelay
            interval: 15
            onTriggered: {
                if (Theme.isMac && !root.sidebarPeekSuppressed)
                    root.sidebarPeeked = true;
                else if (!Theme.isMac)
                    sidebarOverlay.open();
            }
        }
        Timer {
            id: peekHideDelay
            interval: 350
            onTriggered: {
                if (!dockHover.hovered && root.sidebarCollapsed)
                    root.sidebarPeeked = false;
            }
        }
    }

    // the window can still be dragged by its top edge while collapsed
    WindowDragRegion {
        x: 0
        y: 0
        width: parent.width
        height: Theme.cardMargin
        visible: root.sidebarCollapsed && !root.contentFullScreen
    }

    Popup {
        id: sidebarOverlay
        readonly property int shadowPad: 16

        popupType: Popup.Window
        modal: false
        focus: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: shadowPad
        x: -shadowPad
        y: Theme.space1 - shadowPad
        width: Prefs.sidebarWidth + 2 * shadowPad
        height: root.height - 2 * Theme.space1 + 2 * shadowPad

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationMid; easing.type: Easing.OutCubic }
            NumberAnimation { property: "x"; from: -sidebarOverlay.width * 0.25; to: -sidebarOverlay.shadowPad; duration: Theme.durationMid; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast; easing.type: Easing.InQuad }
        }

        background: Item {
            RectangularShadow {
                anchors.fill: overlayCard
                radius: overlayCard.radius
                blur: 24
                offset.x: 2
                color: Theme.shadow
            }
            Rectangle {
                id: overlayCard
                anchors.fill: parent
                anchors.margins: sidebarOverlay.shadowPad
                radius: Theme.radiusCard
                color: Theme.sidebarBg
                border.width: 1
                border.color: Theme.cardBorder
            }
        }

        contentItem: Item {
            Loader {
                id: overlayLoader
                anchors.fill: parent
                active: true
                sourceComponent: sidebarComponent
                onLoaded: item.overlay = true
            }

            HoverHandler {
                id: overlayHover
                onHoveredChanged: if (hovered) hideDelay.stop(); else hideDelay.restart()
            }
        }

        Timer {
            id: hideDelay
            interval: 350
            onTriggered: {
                // a native menu opened from the overlay takes the pointer with it
                if (overlayHover.hovered || (overlayLoader.item && overlayLoader.item.menuOpen))
                    hideDelay.restart();
                else
                    sidebarOverlay.close();
            }
        }
        onOpened: hideDelay.restart()
    }

    CommandBar {
        id: commandBar
        quickActions: [
            { label: "Toggle Sidebar", icon: "qrc:/QT_Illuminate/ui/ui/icons/panel-left.svg", run: () => root.toggleSidebar() },
            { label: "Open Settings", icon: "qrc:/QT_Illuminate/ui/ui/icons/more-vertical.svg", run: () => root.openSettings() },
            { label: "Downloads", icon: "qrc:/QT_Illuminate/ui/ui/icons/download.svg", run: () => downloadsPanel.toggle() },
            { label: "Find in Page", icon: "qrc:/QT_Illuminate/ui/ui/icons/search.svg", run: () => findBar.open() },
            { label: "Copy URL", icon: "qrc:/QT_Illuminate/ui/ui/icons/copy.svg", run: () => Browser.copyActiveUrl() },
            { label: "Developer Tools", icon: "qrc:/QT_Illuminate/ui/ui/icons/activity.svg", run: () => Browser.toggleDevTools() },
            { label: "Memory Usage", icon: "qrc:/QT_Illuminate/ui/ui/icons/activity.svg", run: () => Browser.newTab("illuminate://memory") }
        ]
    }

    // frameless windows lose the native resize border
    ResizeGrips {
        anchors.fill: parent
        visible: root.frameless && root.visibility === Window.Windowed
        z: 1000
        onRequestSystemResize: edges => root.startSystemResize(edges)
    }

    KeyboardShortcuts {
        browser: Browser
        profileManager: ProfileManager
        logger: Logger
        appMenu: AppMenu
        shortcuts: Shortcuts
        findBar: findBar
        zoomIndicator: zoomIndicator
        downloadsPanel: downloadsPanel
        onSettingsRequested: root.openSettings()
        onCommandBarRequested: mode => root.openCommandBar(mode)
        onSidebarToggleRequested: root.toggleSidebar()
        onBookmarkToggleRequested: root.toggleBookmark()
        onPrintRequested: root.printActivePage()
        onSavePdfRequested: root.savePdfActivePage()
        onFullScreenRequested: root.toggleFullScreen()
        onCloseWindowRequested: root.requestWindowClose()
        onProfilePickerRequested: root.openProfileSelector()
        onProfileSwitchRequested: profile => root.switchProfile(profile)
        onWindowRequested: function (action) {
            if (action === "minimize") {
                root.showMinimized();
            } else if (root.visibility === Window.Maximized) {
                root.showNormal();
            } else {
                root.showMaximized();
            }
        }
        onAboutRequested: aboutDialog.open()
        // aboutToQuit saves the session and shuts CEF down
        onQuitRequested: Qt.quit()
    }

    Connections {
        target: root.pointerLockEmu
        function onActiveChanged(a) {
            if (!a) {
                const tab = viewRepeater.itemAt(Browser.tabModel.activeIndex) as TabSlot;
                if (tab && tab.pointerLocked)
                    tab.releaseLock();
            }
        }
        function onMovementReady(dx, dy) {
            const wv = viewStack.activeWebView;
            if (!wv)
                return;

            const rx = Math.round(dx);
            const ry = Math.round(dy);
            if (rx === 0 && ry === 0)
                return;
            wv.runJavaScript("window.__illuminate__onLockDelta && window.__illuminate__onLockDelta("
                + rx + "," + ry + ")");
        }
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequence: "Esc"
        enabled: root.pointerLockActive
        onActivated: root.releasePointerLock()
    }
}