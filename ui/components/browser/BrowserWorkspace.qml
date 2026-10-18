import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: workspace
    required property var browserWindow
    required property var themePicker

    property alias viewStack: viewStack
    property alias findBar: findBar
    property alias zoomIndicator: zoomIndicator
    property alias dockLoader: dockLoader
    property alias overlayLoader: overlayLoader
    property alias sidebarOverlay: sidebarOverlay
    readonly property real dockWidth: dock.fullWidth

    anchors.fill: parent

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            id: dock
            Layout.fillHeight: true
            readonly property real fullWidth: dockLoader.item ? dockLoader.item["implicitWidth"] : 0 // qmllint disable missing-property
            property real targetWidth: browserWindow.sidebarDockCollapsed || browserWindow.contentFullScreen
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
                    browserWindow.sidebarDockCollapsed = true;
                    browserWindow.sidebarPeeked = false;
                    browserWindow.sidebarPeekSuppressed = true;
                }
            }

            Loader {
                id: dockLoader
                width: dock.fullWidth
                height: parent.height
                sourceComponent: sidebarComponent
                Component.onCompleted: {
                    x = browserWindow.sidebarDockCollapsed ? -width : 0;
                    opacity = browserWindow.sidebarDockCollapsed ? 0 : 1;
                }
                onWidthChanged: if (browserWindow.sidebarDockCollapsed && !dockSlideOut.running)
                    x = -width;
            }
        }

        WebContentCard {
            id: card
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: browserWindow.contentFullScreen ? 0 : Theme.cardMargin
            radius: browserWindow.contentFullScreen ? 0 : Theme.radiusCard
            shadowEnabled: !browserWindow.contentFullScreen
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
                        onVisibleChanged: browserWindow.findBarOpen = visible
                    }

                    ZoomIndicator {
                        id: zoomIndicator
                        webView: viewStack.activeWebView
                    }

                    Connections {
                        target: Browser
                        enabled: !browserWindow.retiring
                        function onActiveIndexChanged() {
                            findBar.close();
                            viewStack.refreshActiveWebView();
                        }
                        function onNewTabOpened() {
                            browserWindow.openCommandBar("new");
                        }

                        function onCloseWindowRequested() {
                            browserWindow.requestWindowClose();
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
                        model: browserWindow.retiring ? null : Browser.tabModel

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
            themePicker: workspace.themePicker
            currentUrl: Browser.activeUrl === "newtab://newtab" ? "" : Browser.activeUrl
            currentTitle: Browser.activeTitle
            currentIconUrl: Browser.activeIconUrl
            isLoading: Browser.activeLoading
            loadProgress: Browser.activeProgress
            canGoBack: viewStack.activeWebView ? viewStack.activeWebView.canGoBack : false
            canGoForward: viewStack.activeWebView ? viewStack.activeWebView.canGoForward : false
            findBar: findBar
            zoomIndicator: zoomIndicator

            onOpenSettings: browserWindow.openSettings()
            onCommandBarRequested: mode => browserWindow.openCommandBar(mode)
            onToggleCollapsed: browserWindow.toggleSidebar()
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
        visible: browserWindow.sidebarCollapsed && !browserWindow.contentFullScreen && (!Theme.isMac || !browserWindow.sidebarPeeked)

        HoverHandler {
            id: revealHover
            onHoveredChanged: {
                if (hovered) {
                    if (!browserWindow.sidebarPeekSuppressed)
                        revealDelay.restart();
                } else {
                    revealDelay.stop();
                    browserWindow.sidebarPeekSuppressed = false;
                }
            }
        }
        Timer {
            id: revealDelay
            // Filter accidental edge passes while still feeling immediate.
            interval: 95
            onTriggered: {
                if (Theme.isMac && !browserWindow.sidebarPeekSuppressed) {
                    browserWindow.sidebarPeeked = true;
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
        visible: browserWindow.sidebarCollapsed && !browserWindow.contentFullScreen
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
        height: browserWindow.height - 2 * Theme.space1 + 2 * shadowPad

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
        onClosed: browserWindow.sidebarPeeked = false
    }

}
