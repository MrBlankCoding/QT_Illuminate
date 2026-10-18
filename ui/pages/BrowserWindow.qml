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
    visibility: Window.Maximized
    width: 1280
    height: 840
    minimumWidth: 640
    minimumHeight: 420
    title: (Browser.activeTitle || "New Tab") + " — QT_Illuminate"
    color: Theme.sidebarBg
    readonly property bool frameless: !Theme.isMac
    flags: frameless
        ? Qt.Window | Qt.FramelessWindowHint
        : Qt.Window | (Theme.isMac ? Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint : 0)
    readonly property bool contentFullScreen: workspace.viewStack.activeWebView ? workspace.viewStack.activeWebView.fullScreen : false
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
        if (workspace.findBar.visible)
            workspace.findBar.dismiss();
        if (commandBar.visible)
            commandBar.close();
        if (workspace.viewStack.activeWebView)
            workspace.viewStack.activeWebView.forceActiveFocus();
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
            const buttonsVisible = fullscreen || !root.sidebarCollapsed;
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
        else if (root.contentFullScreenShown && workspace.viewStack.activeWebView)
            workspace.viewStack.activeWebView.exitFullScreen();
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
            windowDialogs.closeDialog.open()
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
        windowDialogs.closeDialog.open()
    }

    readonly property bool sidebarCollapsed: Prefs.sidebarCollapsed
    property bool sidebarDockCollapsed: Prefs.sidebarCollapsed
    onSidebarCollapsedChanged: {
        root.syncMacWindowButtons();
        if (!root.sidebarCollapsed) {
            workspace.stopDockSlideOut();
            root.sidebarDockCollapsed = false;
            workspace.dockLoader.x = -workspace.dockLoader.width;
            workspace.dockLoader.opacity = 0;
            Qt.callLater(workspace.startDockSlideIn);
        } else {
            if (!root.sidebarDockCollapsed)
                workspace.startDockSlideOut();
        }
    }

    function toggleSidebar() {
        Prefs.sidebarCollapsed = !root.sidebarCollapsed;
    }

    function raiseActiveWebView() {
        if (workspace.viewStack.activeWebView)
            workspace.viewStack.activeWebView.refreshNativeView(true);
    }

    // Route sidebar shortcuts to the single dock instance.
    function forEachSidebar(action) {
        if (workspace.dockLoader.item)
            action(workspace.dockLoader.item);
    }

    function openCommandBar(mode) {
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



    WindowDialogs {
        id: windowDialogs
        browserWindow: root
    }

    PrintController {
        id: printController
        activeWebView: workspace.viewStack.activeWebView
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
        AppMenu.attach(root);
    }

    Component.onDestruction: AppMenu.detach(root)

    BrowserWorkspace {
        id: workspace
        browserWindow: root
        themePicker: themePicker
    }

    CommandBar {
        id: commandBar
        onVisibleChanged: root.syncInputOverlayOpen()
        quickActions: [
            { label: "Toggle Sidebar", icon: "qrc:/QT_Illuminate/ui/icons/panel-left.svg", run: () => root.toggleSidebar() },
            { label: "Open Settings", icon: "qrc:/QT_Illuminate/ui/icons/more-vertical.svg", run: () => root.openSettings() },
            { label: "Downloads", icon: "qrc:/QT_Illuminate/ui/icons/download.svg", run: () => Browser.newTab("chrome://downloads/") },
            { label: "Find in Page", icon: "qrc:/QT_Illuminate/ui/icons/search.svg", run: () => workspace.findBar.open() },
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
        x: workspace.dockWidth + Theme.cardMargin - 6
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
            findBar: workspace.findBar
            zoomIndicator: workspace.zoomIndicator

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
        onAboutRequested: windowDialogs.aboutDialog.open()
        // aboutToQuit saves the session and shuts CEF down
        onQuitRequested: Qt.quit()
    }

}
