import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: root

    property string currentUrl: ""
    property string currentTitle: ""
    property string currentIconUrl: ""
    property bool isLoading: false
    property int loadProgress: 0
    property bool canGoBack: false
    property bool canGoForward: false

    property var findBar: null
    property var zoomIndicator: null
    property var downloadsPanel: null
    property var themePicker: null

    // floating over the page while collapsed: its own window, so it draws its
    // own window controls and must act on the browser window, not itself
    property bool overlay: false
    property var targetWindow: root.Window.window

    signal openSettings
    signal switchToProfile(var profile)
    signal openProfileSelector
    signal commandBarRequested(string mode)   // "new" | "edit"
    signal toggleCollapsed

    readonly property bool isFullScreen: root.targetWindow ? root.targetWindow.visibility === Window.FullScreen : false
    readonly property bool customWindowControls: !Theme.isMac && !isFullScreen
    readonly property bool menuOpen: profileMenu.visible || overflowMenu.visible

    // live width while the edge is dragged; the preference is only written on release
    property real dragWidth: -1
    implicitWidth: dragWidth >= 0 ? dragWidth : Prefs.sidebarWidth

    function toggleBookmark() {
        if (root.currentUrl === "")
            return;
        Bookmarks.toggleBookmark(root.currentTitle, root.currentUrl, root.currentIconUrl);
    }

    function avatarColorFor(profile) {
        return profile && profile.color && profile.color.length > 0 ? profile.color : "#4A90E2";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.sidebarPadding
        // the card's own margin is the gap on the right
        anchors.rightMargin: root.overlay ? Theme.sidebarPadding : 0
        anchors.bottomMargin: Theme.sidebarPadding
        spacing: Theme.space2

        // title strip: window controls + navigation, and a window drag handle
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.titleBarHeight

            WindowDragRegion {
                anchors.fill: parent
                // it would move the overlay's own window
                enabled: !root.overlay
            }

            RowLayout {
                anchors.fill: parent
                spacing: 2

                Item {
                    visible: Theme.isMac && !root.isFullScreen && !root.overlay
                    Layout.preferredWidth: Theme.trafficLightW - Theme.sidebarPadding
                }

                WindowControls {
                    visible: root.customWindowControls
                    targetWindow: root.targetWindow
                    buttonWidth: Theme.iconButton + 2
                    buttonHeight: Theme.iconButton
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                }

                SidebarButton {
                    icon: "qrc:/QT_Illuminate/ui/icons/panel-left.svg"
                    iconSize: 15
                    onClicked: root.toggleCollapsed()
                }

                SidebarButton {
                    icon: "qrc:/QT_Illuminate/ui/icons/chevron-left.svg"
                    iconSize: 18
                    enabled: root.canGoBack
                    onClicked: Browser.goBack()
                }
                SidebarButton {
                    icon: "qrc:/QT_Illuminate/ui/icons/chevron-right.svg"
                    iconSize: 18
                    enabled: root.canGoForward
                    onClicked: Browser.goForward()
                }
                SidebarButton {
                    icon: root.isLoading ? "qrc:/QT_Illuminate/ui/icons/x.svg" : "qrc:/QT_Illuminate/ui/icons/rotate-cw.svg"
                    iconSize: 15
                    enabled: root.currentUrl !== ""
                    onClicked: Browser.reload()
                }
            }
        }

        AddressPill {
            id: addressPill
            Layout.fillWidth: true
            currentUrl: root.currentUrl
            isLoading: root.isLoading
            loadProgress: root.loadProgress
            onClicked: root.commandBarRequested(root.currentUrl === "" ? "new" : "edit")
            onToggleBookmark: root.toggleBookmark()
        }

        EssentialsGrid {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space1
            activeUrl: root.currentUrl
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.leftMargin: Theme.space2
            Layout.rightMargin: Theme.space2
            Layout.topMargin: Theme.space1
            visible: Bookmarks.count > 0
            color: Theme.itemHover
        }

        // "+ New Tab", styled as a tab row above the open tabs
        Item {
            id: newTabRow
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.tabRowHeight
            scale: newTabTap.pressed ? Theme.pressScale : 1
            Behavior on scale { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusTab
                color: newTabTap.pressed ? Theme.itemPressed : newTabHover.hovered ? Theme.itemHover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space3 - 2
                spacing: Theme.space2 + 2

                LucideIcon {
                    size: Theme.faviconSize
                    source: "qrc:/QT_Illuminate/ui/icons/plus.svg"
                    color: newTabHover.hovered ? Theme.text : Theme.textMuted
                }
                Text {
                    Layout.fillWidth: true
                    text: "New Tab"
                    color: newTabHover.hovered ? Theme.text : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeM
                    elide: Text.ElideRight
                }
            }

            HoverHandler {
                id: newTabHover
            }
            TapHandler {
                id: newTabTap
                onTapped: root.commandBarRequested("new")
            }
        }

        ListView {
            id: tabList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds
            model: Browser.tabModel

            property bool reordering: false

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            function revealActive() {
                const i = Browser.tabModel.activeIndex;
                if (i >= 0 && i < tabList.count)
                    tabList.positionViewAtIndex(i, ListView.Contain);
            }
            Connections {
                target: Browser.tabModel
                function onActiveIndexChanged() { Qt.callLater(tabList.revealActive) }
            }

            Timer {
                id: reorderSettle
                interval: Theme.durationSlow
                onTriggered: tabList.reordering = false
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationMid; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.durationMid; easing.type: Easing.OutCubic }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast }
            }
            displaced: Transition {
                enabled: !tabList.reordering
                NumberAnimation { properties: "y"; duration: Theme.durationMid; easing.type: Easing.InOutQuad }
            }
            move: Transition {
                enabled: !tabList.reordering
                NumberAnimation { properties: "y"; duration: Theme.durationMid; easing.type: Easing.InOutQuad }
            }

            delegate: TabItem {
                id: tabItemDelegate
                width: tabList.width
                height: tabItemDelegate.tabUrl === "newtab://newtab" ? 0 : Theme.tabRowHeight
                tabCount: tabList.count
                isActive: index === Browser.tabModel.activeIndex
                z: dragging ? 2 : 1

                onActivated: Browser.activateTab(index)
                onCloseClicked: Browser.closeTab(index)
                onReorderRequested: targetIndex => {
                    tabList.reordering = true;
                    reorderSettle.restart();
                    Browser.tabModel.moveTab(index, targetIndex);
                }
            }

            TapHandler {
                onDoubleTapped: eventPoint => {
                    const p = eventPoint.position;
                    if (!tabList.itemAt(p.x + tabList.contentX, p.y + tabList.contentY))
                        root.commandBarRequested("new");
                }
            }
        }

        // footer: profile, downloads, overflow menu
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.iconButton
            spacing: 2

            Item {
                Layout.preferredWidth: Theme.iconButton
                Layout.preferredHeight: Theme.iconButton
                scale: profileTap.pressed ? Theme.pressScale : 1
                Behavior on scale { NumberAnimation { duration: Theme.durationFast } }

                Rectangle {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    radius: width / 2
                    color: root.avatarColorFor(ProfileManager.activeProfile)
                    border.color: Theme.text
                    border.width: profileHover.hovered ? 1 : 0
                }
                Text {
                    anchors.centerIn: parent
                    text: (ProfileManager.activeProfile && ProfileManager.activeProfile.name) ? ProfileManager.activeProfile.name.charAt(0).toUpperCase() : "⊕"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.family: Theme.fontFamily
                    color: "white"
                }

                HoverHandler {
                    id: profileHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    id: profileTap
                    onTapped: profileMenu.popup()
                }

                Menu {
                    id: profileMenu
                    popupType: Popup.Native

                    Repeater {
                        model: ProfileManager.profiles

                        MenuItem {
                            required property var modelData
                            text: {
                                const nm = modelData.name || "Unnamed";
                                return modelData === ProfileManager.activeProfile ? nm + "  ✓" : nm;
                            }
                            enabled: modelData !== ProfileManager.activeProfile
                            onTriggered: root.switchToProfile(modelData)
                        }
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Select Profile…"
                        onTriggered: root.openProfileSelector()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            SidebarButton {
                visible: root.downloadsPanel && root.downloadsPanel.downloadCount > 0
                icon: "qrc:/QT_Illuminate/ui/icons/download.svg"
                iconSize: 18
                active: root.downloadsPanel && root.downloadsPanel.visible
                onClicked: root.downloadsPanel.toggle()

                // something is still downloading
                Rectangle {
                    visible: root.downloadsPanel && root.downloadsPanel.activeCount > 0
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 4
                }
            }

            SidebarButton {
                icon: "qrc:/QT_Illuminate/ui/icons/more-vertical.svg"
                iconSize: 18
                active: overflowMenu.visible
                onClicked: overflowMenu.popup()

                Menu {
                    id: overflowMenu
                    popupType: Popup.Native

                    // the application menu, for platforms without a global menu bar
                    Instantiator {
                        model: AppMenu.native ? [] : AppMenu.tree
                        delegate: AppSubMenu {
                            required property var modelData
                            node: modelData
                        }
                        onObjectAdded: (index, object) => overflowMenu.insertMenu(index, object)
                        onObjectRemoved: (index, object) => overflowMenu.removeMenu(object)
                    }
                    MenuSeparator {
                        visible: !AppMenu.native
                    }

                    MenuItem {
                        text: "New Tab"
                        onTriggered: root.commandBarRequested("new")
                    }

                    MenuItem {
                        text: qsTr("Theme…")
                        onTriggered: root.themePicker && root.themePicker.open()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Zoom In"
                        onTriggered: root.zoomIndicator && root.zoomIndicator.zoomBy(0.1)
                    }
                    MenuItem {
                        text: "Zoom Out"
                        onTriggered: root.zoomIndicator && root.zoomIndicator.zoomBy(-0.1)
                    }
                    MenuItem {
                        text: "Reset Zoom" + (root.zoomIndicator ? " (" + root.zoomIndicator.zoomPercent + "%)" : "")
                        onTriggered: root.zoomIndicator && root.zoomIndicator.zoomReset()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Find in Page…"
                        onTriggered: root.findBar && root.findBar.open()
                    }

                    MenuItem {
                        text: addressPill.isBookmarked ? "Remove Bookmark" : "Bookmark This Page"
                        enabled: root.currentUrl !== ""
                        onTriggered: root.toggleBookmark()
                    }

                    MenuItem {
                        text: "Downloads"
                        onTriggered: root.downloadsPanel && root.downloadsPanel.toggle()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Developer Tools"
                        onTriggered: Browser.toggleDevTools()
                    }

                    MenuItem {
                        text: "Memory Usage"
                        onTriggered: Browser.newTab("illuminate://memory")
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Settings…"
                        onTriggered: root.openSettings()
                    }
                }
            }
        }
    }



    // drag the right edge to resize; it straddles the gap before the card,
    // which is plain QML (the page's native view would swallow the events)
    MouseArea {
        id: resizeHandle
        enabled: !root.overlay
        x: root.width - width / 2
        width: Theme.resizeHandleW
        height: root.height
        z: 10
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeHorCursor

        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const x = mapToItem(root, mouse.x, 0).x;
            // leave the page a usable width
            const max = Math.min(Prefs.sidebarMaxWidth, root.targetWindow.width - 360);
            root.dragWidth = Math.max(Prefs.sidebarMinWidth, Math.min(max, x));
        }
        onReleased: {
            if (root.dragWidth >= 0)
                Prefs.sidebarWidth = Math.round(root.dragWidth);
            root.dragWidth = -1;
        }
    }
}
