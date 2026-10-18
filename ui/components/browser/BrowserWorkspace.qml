import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: workspace
    required property var browserWindow
    required property var themePicker

    property alias viewStack: viewStack
    property alias zoomIndicator: zoomIndicator
    property alias dockLoader: dockLoader
    readonly property real dockWidth: dock.fullWidth

    function stopDockSlideOut() { dockSlideOut.stop(); }
    function startDockSlideOut() { dockSlideOut.start(); }
    function startDockSlideIn() { dockSlideIn.start(); }

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

                    ZoomIndicator {
                        id: zoomIndicator
                        webView: viewStack.activeWebView
                    }

                    Connections {
                        target: Browser
                        enabled: !browserWindow.retiring
                        function onActiveIndexChanged() {
                            viewStack.refreshActiveWebView();
                        }
                        function onNewTabOpened() {
                            browserWindow.openCommandBar("new");
                        }

                        function onCloseWindowRequested() {
                            browserWindow.requestWindowClose();
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
            zoomIndicator: zoomIndicator

            onOpenSettings: browserWindow.openSettings()
            onCommandBarRequested: mode => browserWindow.openCommandBar(mode)
            onToggleCollapsed: browserWindow.toggleSidebar()
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

}
