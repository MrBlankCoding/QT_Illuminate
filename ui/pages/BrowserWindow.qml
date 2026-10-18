import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Window {
    id: root
    // the root object is not shown for us; this is the app's only window at
    // startup, so it opens itself
    visible: true
    // Let the native window system choose the usable screen bounds on macOS.
    // A fixed content size can leave the window short of the available frame,
    // especially with the transparent full-size title bar enabled below.
    visibility: Theme.isMac ? Window.Maximized : Window.Windowed
    width: 1280
    height: 840
    minimumWidth: 640
    minimumHeight: 420
    title: (Browser.activeTitle || "New Tab") + " — QT_Illuminate"
    color: Theme.chromeBg
    readonly property bool frameless: !Theme.isMac
    flags: frameless
        ? Qt.Window | Qt.FramelessWindowHint
        : Qt.Window | (Theme.isMac ? Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint : 0)
    readonly property bool contentFullScreen: viewStack.activeWebView ? viewStack.activeWebView.fullScreen : false
    property bool fullScreenForContent: false
    property bool contentFullScreenShown: false
    property int visibilityBeforeContentFullScreen: Window.Windowed
    property int visibilityBeforeWindowFullScreen: Window.Windowed
    property rect geometryBeforeFullScreen: Qt.rect(0, 0, 1280, 840)
    property bool restoreGeometryAfterFullScreen: false
    property bool findBarOpen: false
    property var uiFocusClaims: []
    property bool inputOverlayOpen: false

    function syncInputOverlayOpen() {
        const commandVisible = commandBar && commandBar.visible;
        root.inputOverlayOpen = commandVisible || root.findBarOpen || root.uiFocusClaims.length > 0;
    }

    function claimUiFocus(owner) {
        if (!owner || root.uiFocusClaims.includes(owner))
            return;
        root.uiFocusClaims = root.uiFocusClaims.concat([owner]);
        root.syncInputOverlayOpen();
    }

    function releaseUiFocus(owner) {
        if (!owner)
            return;
        root.uiFocusClaims = root.uiFocusClaims.filter(claim => claim !== owner);
        root.syncInputOverlayOpen();
    }

    onFindBarOpenChanged: root.syncInputOverlayOpen()
    function returnFocusToWeb() {
        root.uiFocusClaims = [];
        root.syncInputOverlayOpen();
        if (findBar.visible)
            findBar.dismiss();
        if (commandBar.visible)
            commandBar.close();
        if (viewStack.activeWebView)
            viewStack.activeWebView.forceActiveFocus();
    }
    function rememberWindowGeometry() {
        if (root.visibility === Window.FullScreen || root.restoreGeometryAfterFullScreen)
            return;
        root.geometryBeforeFullScreen = Qt.rect(root.x, root.y, root.width, root.height);
        root.visibilityBeforeWindowFullScreen = root.visibility;
    }

    onXChanged: root.rememberWindowGeometry()
    onYChanged: root.rememberWindowGeometry()
    onWidthChanged: root.rememberWindowGeometry()
    onHeightChanged: root.rememberWindowGeometry()

    function restoreWindowAfterFullScreen() {
        // AppKit preserves/restores the exact NSWindow frame around its native
        // fullscreen transition. The QML fallback is for frameless platforms.
        root.restoreGeometryAfterFullScreen = !Theme.isMac
            && root.visibilityBeforeWindowFullScreen !== Window.Maximized;
        if (root.visibilityBeforeWindowFullScreen === Window.Maximized) {
            root.showMaximized();
        } else {
            root.showNormal();
        }
    }

    function toggleFullScreen() {
        if (root.visibility === Window.FullScreen) {
            root.restoreWindowAfterFullScreen();
            return;
        }
        root.rememberWindowGeometry();
        root.showFullScreen();
    }

    function syncMacWindowButtons() {
        if (Theme.isMac) {
            const fullscreen = root.visibility === Window.FullScreen;
            const buttonsVisible = fullscreen || !root.sidebarCollapsed || root.sidebarPeeked;
            WindowHelper.setWindowButtonsVisible(root, buttonsVisible);
        }
    }

    onContentFullScreenChanged: {
        if (root.retiring)
            return;
        if (contentFullScreen) {
            if (root.visibility !== Window.FullScreen) {
                root.visibilityBeforeContentFullScreen = root.visibility;
                root.rememberWindowGeometry();
                root.fullScreenForContent = true;
                root.showFullScreen();
            }
        } else if (root.fullScreenForContent) {
            root.fullScreenForContent = false;
            root.contentFullScreenShown = false;
            root.restoreWindowAfterFullScreen();
        }
    }

    onVisibilityChanged: {
        root.syncMacWindowButtons();
        if (root.visibility !== Window.FullScreen) {
            root.visibilityBeforeWindowFullScreen = root.visibility;
            if (root.restoreGeometryAfterFullScreen) {
                fullScreenGeometryRestoreTimer.restart();
            }
        }

        if (!root.contentFullScreen)
            return;
        if (root.visibility === Window.FullScreen)
            root.contentFullScreenShown = true;
        else if (root.contentFullScreenShown && viewStack.activeWebView)
            viewStack.activeWebView.exitFullScreen();
    }

    // Native fullscreen transitions can report Windowed before AppKit has
    // finished animating back to the saved frame. Restore after that transition.
    Timer {
        id: fullScreenGeometryRestoreTimer
        interval: 700
        repeat: false
        onTriggered: {
            if (!root.restoreGeometryAfterFullScreen || root.visibility === Window.FullScreen)
                return;
            const previous = root.geometryBeforeFullScreen;
            root.x = previous.x;
            root.y = previous.y;
            root.width = previous.width;
            root.height = previous.height;
            root.restoreGeometryAfterFullScreen = false;
        }
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
            if (!root.replacedByNewWindow)
                root.windowClosed()
            Browser.releaseWindow(root)
            return;
        }
        close.accepted = false
        closeDialog.open()
    }

    readonly property bool sidebarCollapsed: Prefs.sidebarCollapsed
    property bool sidebarPeeked: false
    property bool sidebarPeekSuppressed: false
    property bool sidebarDockCollapsed: Prefs.sidebarCollapsed
    onSidebarPeekedChanged: {
        root.syncMacWindowButtons();
    }
    onSidebarCollapsedChanged: {
        root.syncMacWindowButtons();
        if (!root.sidebarCollapsed) {
            dockSlideOut.stop();
            sidebarOverlay.close();
            root.sidebarPeeked = false;
            root.sidebarPeekSuppressed = false;
            root.sidebarDockCollapsed = false;
            dockLoader.x = -dockLoader.width;
            dockLoader.opacity = 0;
            Qt.callLater(dockSlideIn.start);
        } else {
            if (!root.sidebarDockCollapsed) {
                dockSlideOut.start();
            } else {
                root.sidebarPeeked = false;
                root.sidebarPeekSuppressed = true;
            }
        }
    }

    function toggleSidebar() {
        Prefs.sidebarCollapsed = !root.sidebarCollapsed;
    }

    function raiseActiveWebView() {
        if (viewStack.activeWebView)
            viewStack.activeWebView.refreshNativeView(true);
    }

    // the sidebar exists twice when it is collapsed: in the dock and in the
    // peek overlay; a shortcut should reach whichever one is on screen
    function forEachSidebar(action) {
        for (const sidebar of [dockLoader.item, overlayLoader.item]) {
            if (sidebar)
                action(sidebar);
        }
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
            const component = Qt.createComponent("qrc:/QT_Illuminate/ui/pages/SettingsWindow.qml");
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



    Dialog {
        id: closeDialog
        title: "Close window?"
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
                text: "Illuminate is your personal browser for a clearer, more focused web."
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

    PrintController {
        id: printController
        activeWebView: viewStack.activeWebView
    }

    function printActivePage() { printController.printActivePage(); }
    function savePdfActivePage() { printController.savePdfActivePage(); }
    function openSystemPrintFor(view) { printController.openSystemPrintFor(view); }
    function onPdfPrintingFinished(filePath, success) { printController.onPdfPrintingFinished(filePath, success); }

    Component.onCompleted: {
        Qt.callLater(root.syncInputOverlayOpen);
        Logger.info("BrowserWindow", "Window ready, platform=" + Qt.platform.os);
        WindowHelper.applyTitleBarStyle(root, Theme.titleBarHeight);
        root.syncMacWindowButtons();
        WindowHelper.setWindowTransparent(root, Theme.transparentChrome, Theme.isDark);
        AppMenu.attach(root);
    }

    Component.onDestruction: AppMenu.detach(root)

    Connections {
        // keep the native vibrancy appearance in sync with the system scheme
        target: Application.styleHints
        function onColorSchemeChanged() {
            if (Browser.themeMode === "system")
                WindowHelper.setWindowTransparent(root, Theme.transparentChrome, Theme.isDark);
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            id: dock
            Layout.fillHeight: true
            readonly property real fullWidth: dockLoader.item ? dockLoader.item["implicitWidth"] : 0 // qmllint disable missing-property
            property real targetWidth: root.sidebarDockCollapsed || root.contentFullScreen
                ? 0 : fullWidth
            Layout.preferredWidth: targetWidth
            clip: true
            visible: targetWidth > 0 || width > 0

            ParallelAnimation {
                id: dockSlideIn
                NumberAnimation {
                    target: dockLoader
                    property: "x"
                    to: 0
                    duration: 220
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: dockLoader
                    property: "opacity"
                    to: 1
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            ParallelAnimation {
                id: dockSlideOut
                NumberAnimation {
                    target: dockLoader
                    property: "x"
                    to: -dockLoader.width
                    duration: 190
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: dockLoader
                    property: "opacity"
                    to: 0
                    duration: 150
                    easing.type: Easing.InCubic
                }
                onFinished: {
                    root.sidebarDockCollapsed = true;
                    root.sidebarPeeked = false;
                    root.sidebarPeekSuppressed = true;
                }
            }

            Loader {
                id: dockLoader
                width: dock.fullWidth
                height: parent.height
                sourceComponent: sidebarComponent
                Component.onCompleted: {
                    x = root.sidebarDockCollapsed ? -width : 0;
                    opacity = root.sidebarDockCollapsed ? 0 : 1;
                }
                onWidthChanged: if (root.sidebarDockCollapsed && !dockSlideOut.running)
                    x = -width;
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

                    Component.onCompleted: {
                        Qt.callLater(viewStack.refreshActiveWebView);
                        if (activeSplitIds.length === 2)
                            Browser.sidebar.prepareSplit(activeSplitIds[0]);
                    }

                    FindBar {
                        id: findBar
                        webView: viewStack.activeWebView
                        focusRouter: root
                        onVisibleChanged: root.findBarOpen = visible
                    }

                    ZoomIndicator {
                        id: zoomIndicator
                        webView: viewStack.activeWebView
                    }

                    Connections {
                        target: Browser
                        enabled: !root.retiring
                        function onActiveIndexChanged() {
                            findBar.close();
                            viewStack.refreshActiveWebView();
                        }
                        function onNewTabOpened() {
                            root.openCommandBar("new");
                        }

                        function onCloseWindowRequested() {
                            root.requestWindowClose();
                        }

                        function onTransparentChromeChanged() {
                            WindowHelper.setWindowTransparent(root, Browser.transparentChrome, Theme.isDark);
                        }

                        function onThemeModeChanged() {
                            WindowHelper.setWindowTransparent(root, Theme.transparentChrome, Theme.isDark);
                        }
                    }

                    Connections {
                        // On macOS the CEF page is a child NSWindow. Restore it
                        // after Qt moves keyboard focus into sidebar controls.
                        // Sync its frame without reordering native windows on
                        // every focus change (which flashes the macOS menu bar).
                        target: root
                        function onActiveFocusItemChanged() {
                            Qt.callLater(() => {
                                if (viewStack.activeWebView)
                                    viewStack.activeWebView.refreshNativeView(false);
                            });
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

                    Connections {
                        target: Browser.tabModel
                        function onRowsMoved() {
                            // Reordering can change delegate stacking without
                            // changing the active index. Restore the selected
                            // native CEF view after the delegates settle.
                            Qt.callLater(() => {
                                viewStack.refreshActiveWebView();
                                if (viewStack.activeWebView)
                                    viewStack.activeWebView.refreshNativeView(true);
                            });
                        }
                    }

                    readonly property var activeSplitIds: {
                        const tab = Browser.tabModel.tabAt(Browser.tabModel.activeIndex);
                        const revision = Browser.sidebar.structureRevision;
                        return tab && revision >= 0 ? Browser.sidebar.splitTabs(tab.id) : [];
                    }
                    readonly property string activeSplitKey: activeSplitIds.join("|")
                    onActiveSplitKeyChanged: if (activeSplitIds.length === 2)
                        Browser.sidebar.prepareSplit(activeSplitIds[0]);
                }
            }
        }
    }

    Component {
        id: sidebarComponent

        Sidebar {
            targetWindow: root
            themePicker: themePicker
            currentUrl: Browser.activeUrl === "newtab://newtab" ? "" : Browser.activeUrl
            currentTitle: Browser.activeTitle
            currentIconUrl: Browser.activeIconUrl
            isLoading: Browser.activeLoading
            loadProgress: Browser.activeProgress
            canGoBack: viewStack.activeWebView ? viewStack.activeWebView.canGoBack : false
            canGoForward: viewStack.activeWebView ? viewStack.activeWebView.canGoForward : false
            findBar: findBar
            zoomIndicator: zoomIndicator

            onOpenSettings: root.openSettings()
            onCommandBarRequested: mode => root.openCommandBar(mode)
            onToggleCollapsed: root.toggleSidebar()
        }
    }

    Item {
        id: revealEdge
        x: 0
        y: 0
        // Give the pointer a forgiving target; the old 10px strip was easy to
        // skim past, especially while moving along the window edge.
        width: Theme.cardMargin + 8
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
            // Filter accidental edge passes while still feeling immediate.
            interval: 95
            onTriggered: {
                if (Theme.isMac && !root.sidebarPeekSuppressed) {
                    root.sidebarPeeked = true;
                    sidebarOverlay.open();
                } else if (!Theme.isMac) {
                    sidebarOverlay.open();
                }
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
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.OutCubic }
            NumberAnimation { property: "x"; from: -sidebarOverlay.width * 0.16; to: -sidebarOverlay.shadowPad; duration: 240; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 130; easing.type: Easing.InCubic }
            NumberAnimation { property: "x"; to: -sidebarOverlay.width * 0.16; duration: 170; easing.type: Easing.InCubic }
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
                    color: Theme.chromeBg
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
            interval: 500
            onTriggered: {
                // a native menu opened from the overlay takes the pointer with it
                if (overlayHover.hovered || (overlayLoader.item && overlayLoader.item["menuOpen"])) // qmllint disable missing-property
                    hideDelay.restart();
                else
                    sidebarOverlay.close();
            }
        }
        onOpened: hideDelay.restart()
        onClosed: root.sidebarPeeked = false
    }

    CommandBar {
        id: commandBar
        onVisibleChanged: root.syncInputOverlayOpen()
        quickActions: [
            { label: "Toggle Sidebar", icon: "qrc:/QT_Illuminate/ui/icons/panel-left.svg", run: () => root.toggleSidebar() },
            { label: "Open Settings", icon: "qrc:/QT_Illuminate/ui/icons/more-vertical.svg", run: () => root.openSettings() },
            { label: "Downloads", icon: "qrc:/QT_Illuminate/ui/icons/download.svg", run: () => Browser.newTab("chrome://downloads/") },
            { label: "Find in Page", icon: "qrc:/QT_Illuminate/ui/icons/search.svg", run: () => findBar.open() },
            { label: "Copy URL", icon: "qrc:/QT_Illuminate/ui/icons/copy.svg", run: () => Browser.copyActiveUrl() },
            { label: "Developer Tools", icon: "qrc:/QT_Illuminate/ui/icons/activity.svg", run: () => Browser.toggleDevTools() },
            { label: "Memory Usage", icon: "qrc:/QT_Illuminate/ui/icons/activity.svg", run: () => Browser.newTab("illuminate://memory") },
            { label: "History", icon: "qrc:/QT_Illuminate/ui/icons/search.svg", run: () => Browser.newTab("chrome://history/") }
        ]
    }

    ThemePicker {
        id: themePicker
        focusRouter: root
        popupType: Popup.Window
        x: dock.fullWidth + Theme.cardMargin - 6
        y: Math.max(8, Math.round((root.height - implicitHeight) / 2))

        showArrow: true
        arrowOffset: 0
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
        logger: Logger
        appMenu: AppMenu
        shortcuts: Shortcuts
            findBar: findBar
            zoomIndicator: zoomIndicator

        onSettingsRequested: root.openSettings()
        onSpaceSwitchRequested: spaceId => {
            const space = Spaces.spaceById(spaceId);
            if (space)
                Spaces.activeSpace = space;
            else
                Logger.warning("BrowserWindow", "No space with id " + spaceId);
        }
        // the editor lives in the sidebar, which may be in either loader
        onNewSpaceRequested: root.forEachSidebar(sidebar => sidebar.openSpaceEditor(null))
        onCommandBarRequested: mode => root.openCommandBar(mode)
        onSidebarToggleRequested: root.toggleSidebar()
        onBookmarkToggleRequested: root.toggleBookmark()
        onPrintRequested: root.printActivePage()
        onSavePdfRequested: root.savePdfActivePage()
        onFullScreenRequested: root.toggleFullScreen()
        onCloseWindowRequested: root.requestWindowClose()
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

}
