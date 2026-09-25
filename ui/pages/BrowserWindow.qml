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
    readonly property bool frameless: Qt.platform.os !== "osx"
    flags: frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window

    function switchProfile(profile) {
        if (!profile)
            return;
        ProfileManager.activeProfile = profile;
        const component = Qt.createComponent("qrc:/QT_Illuminate/ui/ui/pages/BrowserWindow.qml");
        if (component.status !== Component.Ready) {
            Logger.error("BrowserWindow", "Failed to load window for profile switch: " + component.errorString());
            return;
        }
        const w = component.createObject(null) as Window;
        if (!w)
            return;
        w.show();
        root.close();
    }

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

        // bookmarks bar (new tab page only)
        BookmarksBar {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            visible: Bookmarks.count > 0 && Browser.activeUrl === "newtab://newtab"
        }

        // content area
        Item {
            id: viewStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            property WebEngineView activeWebView: null

            function refreshActiveWebView() {
                const tab = viewRepeater.itemAt(Browser.tabModel.activeIndex) as TabSlot;
                viewStack.activeWebView = tab ? tab.webView : null;
            }

            Component.onCompleted: Qt.callLater(viewStack.refreshActiveWebView)

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
                    viewStack.refreshActiveWebView();
                }
                function onNewTabOpened() {
                    // defer so the new tab's view doesn't steal focus back
                    Qt.callLater(toolbar.focusAddressBar);
                }
            }

            Repeater {
                id: viewRepeater
                model: Browser.tabModel

                delegate: TabSlot {
                    browserWindow: root
                    viewStack: viewStack
                }

                onItemAdded: viewStack.refreshActiveWebView()
                onItemRemoved: viewStack.refreshActiveWebView()
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
        onPrintRequested: root.printActivePage()
        onSavePdfRequested: root.savePdfActivePage()
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
        sequence: "Esc"
        enabled: root.pointerLockActive
        onActivated: root.releasePointerLock()
    }
}