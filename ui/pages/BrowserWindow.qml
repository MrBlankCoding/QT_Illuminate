import QtQuick
import QtQuick.Controls
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
    color: Theme.bg
    readonly property bool frameless: Qt.platform.os !== "osx"
    flags: frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window
    readonly property bool contentFullScreen: viewStack.activeWebView ? viewStack.activeWebView.fullScreen : false
    property bool fullScreenForContent: false
    property bool contentFullScreenShown: false
    property int visibilityBeforeContentFullScreen: Window.Windowed
    property int visibilityBeforeWindowFullScreen: Window.Windowed
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
        root.retire();
    }

    function retire() {
        root.skipCloseConfirm = true
        root.replacedByNewWindow = true
        root.close();
        Qt.callLater(function () { root.destroy(); });
    }

    property Window settingsWindow: null
    property bool skipCloseConfirm: false
    property bool replacedByNewWindow: false
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
            return;
        }
        close.accepted = false
        closeDialog.open()
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
        // before retiring, so the app never has a moment with no window
        picker.show();
        root.retire();
    }

    Dialog {
        id: closeDialog
        title: "Close window?"
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
                onClicked: closeDialog.close()
            }

            PillButton {
                text: "Close window"
                fillColor: Theme.accent
                hoverFillColor: Qt.darker(Theme.accent, 1.1)
                textColor: Theme.onAccent
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
        WindowHelper.applyTitleBarStyle(root, Theme.tabBarHeight);
        // macOS draws the bar at the top of the screen from here on; elsewhere
        // this only tells the tree which window it belongs to
        AppMenu.attach(root);
    }

    Component.onDestruction: AppMenu.detach(root)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // the menu bar, for the platforms that have none of their own
        AppMenuBar {
            Layout.fillWidth: true
            visible: !root.contentFullScreen
        }

        // tab strip
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            visible: !root.contentFullScreen
        }

        // toolbar
        Toolbar {
            id: toolbar
            Layout.fillWidth: true
            z: 100
            visible: !root.contentFullScreen

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
            visible: !root.contentFullScreen && Bookmarks.count > 0 && Browser.activeUrl === "newtab://newtab"

            onNavigate: function (url) {
                Browser.navigate(url);
            }
            onOpenInNewTab: function (url) {
                Browser.newTab(url);
            }
        }

        // content area
        Item {
            id: viewStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            property CefBrowser activeWebView: null

            function refreshActiveWebView() {
                const tab = viewRepeater.itemAt(Browser.tabModel.activeIndex) as TabSlot;
                const next = tab ? tab.webView : null;
                // a background tab can't stay fullscreen
                if (viewStack.activeWebView && viewStack.activeWebView !== next && viewStack.activeWebView.fullScreen)
                    viewStack.activeWebView.exitFullScreen();
                viewStack.activeWebView = next;
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
            Qt.callLater(toolbar.focusAddressBar);
        }

        function onCloseWindowRequested() {
            root.requestWindowClose();
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