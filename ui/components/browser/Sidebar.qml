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
        || sidebarMenu.visible || tabMenu.visible || folderMenu.visible || deleteFolderPopup.visible
        || root.renamingId !== ""

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

        // folders, the "New Tab" header, then the tabs not in a folder
        Item {
            id: tree
            Layout.fillWidth: true
            Layout.fillHeight: true

            // drag state: the row being moved and where it would land
            property string dragId: ""
            property string dragTitle: ""
            property string dragIconUrl: ""
            property string dragKind: ""
            property real dragY: 0
            property string dropTargetId: ""
            property int dropPosition: -1
            property real indicatorX: 0
            property real indicatorY: 0

            function beginDrag(row) {
                tree.dragId = row.nodeId;
                tree.dragKind = row.kind;
                tree.dragTitle = row.model.title || "";
                tree.dragIconUrl = row.kind === "tab" ? (row.model.iconUrl || "") : "";
            }

            function endDrag() {
                if (tree.dragId !== "" && tree.dropTargetId !== "" && tree.dropPosition >= 0)
                    Browser.sidebar.drop(tree.dragId, tree.dropTargetId, tree.dropPosition);
                tree.dragId = "";
                tree.clearTarget();
                scrollTimer.direction = 0;
            }

            function clearTarget() {
                tree.dropTargetId = "";
                tree.dropPosition = -1;
            }

            function dragMove(scenePos) {
                const p = tree.mapFromItem(null, scenePos.x, scenePos.y);
                tree.dragY = p.y;
                const edge = Theme.tabRowHeight;
                scrollTimer.direction = p.y < edge ? -1 : p.y > tree.height - edge ? 1 : 0;
                tree.updateTarget();
            }

            // top or bottom edge of a row: beside it; the middle of a folder: into it
            function updateTarget() {
                const cy = tree.dragY + tabList.contentY;
                let item = tabList.itemAt(tabList.width / 2, cy);
                if (!item)
                    item = tabList.itemAt(tabList.width / 2, cy - tabList.spacing);
                if (!item && tabList.count > 0) {
                    const last = tabList.itemAtIndex(tabList.count - 1);
                    if (last && cy > last.y + last.height)
                        item = last;
                }
                if (!item || !item.nodeId) {
                    tree.clearTarget();
                    return;
                }

                const frac = Math.max(0, Math.min(1, (cy - item.y) / item.height));
                let pos;
                if (item.kind === "folder")
                    pos = frac < 0.25 ? SidebarModel.Before
                        : frac > 0.75 && !item.expanded ? SidebarModel.After
                        : SidebarModel.Into;
                else
                    pos = frac < 0.5 ? SidebarModel.Before : SidebarModel.After;

                if (!Browser.sidebar.canDrop(tree.dragId, item.nodeId, pos)) {
                    tree.clearTarget();
                    return;
                }
                if (item.nodeId !== tree.dropTargetId || pos !== tree.dropPosition) {
                    tree.dropTargetId = item.nodeId;
                    tree.dropPosition = pos;
                    if (pos === SidebarModel.Into && !item.expanded)
                        expandTimer.restart();
                    else
                        expandTimer.stop();
                }
                const gap = tabList.spacing / 2;
                tree.indicatorX = item.indent;
                tree.indicatorY = pos === SidebarModel.Before ? item.y - gap : item.y + item.height + gap;
            }

            Timer {
                id: expandTimer
                interval: Theme.folderHoverExpandMs
                onTriggered: {
                    if (tree.dropPosition === SidebarModel.Into)
                        Browser.sidebar.setExpanded(tree.dropTargetId, true);
                }
            }

            // keep scrolling while a drag hangs at the top or bottom edge
            Timer {
                id: scrollTimer
                property int direction: 0
                interval: 16
                repeat: true
                running: direction !== 0 && tree.dragId !== ""
                onTriggered: {
                    const max = Math.max(0, tabList.contentHeight - tabList.height);
                    tabList.contentY = Math.max(0, Math.min(max, tabList.contentY + direction * 6));
                    tree.updateTarget();
                }
            }

            ListView {
                id: tabList
                anchors.fill: parent
                clip: true
                spacing: 2
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: tree.dragId === ""
                model: Browser.sidebar

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                function revealActive() {
                    const i = Browser.sidebar.rowOf(Browser.tabModel.tabAt(Browser.tabModel.activeIndex)?.id ?? "");
                    if (i >= 0 && i < tabList.count)
                        tabList.positionViewAtIndex(i, ListView.Contain);
                }
                Connections {
                    target: Browser.tabModel
                    function onActiveIndexChanged() { Qt.callLater(tabList.revealActive) }
                }

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationFolder; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.durationFolder; easing.type: Easing.OutCubic }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast }
                }
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: Theme.durationFolder; easing.type: Easing.OutCubic }
                }
                move: Transition {
                    NumberAnimation { properties: "y"; duration: Theme.durationMid; easing.type: Easing.InOutQuad }
                }

                delegate: Item {
                    id: row
                    required property var model
                    required property int index

                    readonly property string nodeId: model.nodeId ?? ""
                    readonly property string kind: model.kind ?? ""
                    readonly property int depth: model.depth ?? 0
                    readonly property bool expanded: model.expanded === true
                    readonly property real indent: Math.min(depth, Theme.sidebarMaxIndent) * Theme.sidebarIndent

                    width: tabList.width
                    height: kind === "header"
                        ? Theme.tabRowHeight + (Browser.sidebar.folderCount > 0 ? Theme.space2 + 1 : 0)
                        : Theme.tabRowHeight
                    opacity: tree.dragId !== "" && tree.dragId === nodeId ? 0.4 : 1
                    z: dragHandler.active ? 2 : 1

                    // a guide line down from each enclosing folder
                    Repeater {
                        model: Math.min(row.depth, Theme.sidebarMaxIndent)
                        Rectangle {
                            required property int index
                            x: index * Theme.sidebarIndent + Theme.space3 - 2 + Theme.faviconSize / 2
                            y: -tabList.spacing / 2
                            width: 1
                            height: row.height + tabList.spacing
                            color: Theme.itemPressed
                        }
                    }

                    Loader {
                        x: row.indent
                        width: row.width - row.indent
                        height: row.height
                        sourceComponent: row.kind === "folder" ? folderComponent
                                       : row.kind === "tab" ? tabComponent
                                       : row.kind === "header" ? headerComponent
                                       : null
                    }

                    Component {
                        id: tabComponent
                        TabItem {
                            model: row.model
                            index: row.index
                            isActive: row.model.active === true
                            dragging: tree.dragId === row.nodeId
                            onActivated: Browser.activateTab(row.model.tabIndex)
                            onCloseClicked: Browser.closeTab(row.model.tabIndex)
                            onContextMenuRequested: root.openTabMenu(row.model)
                        }
                    }

                    Component {
                        id: folderComponent
                        FolderRow {
                            title: row.model.title ?? ""
                            icon: row.model.icon ?? ""
                            expanded: row.expanded
                            editing: root.renamingId !== "" && root.renamingId === row.nodeId
                            dragging: tree.dragId === row.nodeId
                            dropTarget: tree.dropTargetId === row.nodeId && tree.dropPosition === SidebarModel.Into
                            onToggled: Browser.sidebar.toggleFolder(row.nodeId)
                            onRenameRequested: root.renamingId = row.nodeId
                            onRenamed: title => {
                                Browser.sidebar.renameFolder(row.nodeId, title);
                                root.renamingId = "";
                            }
                            onEditingCanceled: root.renamingId = ""
                            onMenuRequested: root.openFolderMenu(row.model)
                        }
                    }

                    // the divider under the folders, and "+ New Tab"
                    Component {
                        id: headerComponent
                        Item {
                            Rectangle {
                                visible: Browser.sidebar.folderCount > 0
                                x: Theme.space2
                                y: Theme.space1
                                width: parent.width - Theme.space2 * 2
                                height: 1
                                color: Theme.itemHover
                            }

                            Item {
                                id: newTabRow
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Theme.tabRowHeight
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
                                    anchors.rightMargin: Theme.space1 + 2
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
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: sidebarMenu.popup()
                                }
                            }
                        }
                    }

                    DragHandler {
                        id: dragHandler
                        target: null
                        enabled: (row.kind === "tab" || row.kind === "folder") && root.renamingId !== row.nodeId
                        onActiveChanged: active ? tree.beginDrag(row) : tree.endDrag()
                        onCentroidChanged: if (active) tree.dragMove(centroid.scenePosition)
                    }
                }

                // where the dragged row would land
                Rectangle {
                    visible: tree.dragId !== "" && tree.dropPosition >= 0 && tree.dropPosition !== SidebarModel.Into
                    x: tree.indicatorX + Theme.space1
                    y: tree.indicatorY - height / 2
                    z: 10
                    width: tabList.width - x - Theme.space1
                    height: 2
                    radius: 1
                    color: Theme.accent
                }

                TapHandler {
                    onDoubleTapped: eventPoint => {
                        const p = eventPoint.position;
                        if (!tabList.itemAt(p.x + tabList.contentX, p.y + tabList.contentY))
                            root.commandBarRequested("new");
                    }
                }

                // empty space: the sidebar's own menu
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: eventPoint => {
                        const p = eventPoint.position;
                        if (!tabList.itemAt(p.x + tabList.contentX, p.y + tabList.contentY))
                            sidebarMenu.popup();
                    }
                }
            }

            // follows the pointer while a row is dragged
            Rectangle {
                visible: tree.dragId !== ""
                x: Theme.space2
                y: Math.max(0, Math.min(tree.height - height, tree.dragY - height / 2))
                z: 20
                width: tree.width - Theme.space2 * 2
                height: Theme.tabRowHeight
                radius: Theme.radiusTab
                color: Theme.itemActive
                border.width: 1
                border.color: Theme.itemActiveBorder
                opacity: 0.92

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space3 - 2
                    anchors.rightMargin: Theme.space2
                    spacing: Theme.space2 + 2

                    Item {
                        Layout.preferredWidth: Theme.faviconSize
                        Layout.preferredHeight: Theme.faviconSize

                        Image {
                            anchors.fill: parent
                            visible: tree.dragKind === "tab" && tree.dragIconUrl !== ""
                            source: visible ? tree.dragIconUrl : ""
                            sourceSize.width: Theme.faviconSize * 2
                            sourceSize.height: Theme.faviconSize * 2
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        LucideIcon {
                            anchors.centerIn: parent
                            visible: tree.dragKind === "folder"
                            size: 16
                            source: "qrc:/QT_Illuminate/ui/icons/folder.svg"
                            color: Theme.text
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: tree.dragTitle
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeM
                        elide: Text.ElideRight
                    }
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
                icon: "qrc:/QT_Illuminate/ui/icons/download.svg"
                iconSize: 18
                onClicked: Browser.newTab("chrome://downloads/")
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
                        text: qsTr("New Folder")
                        onTriggered: root.newFolder()
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
                        onTriggered: Browser.newTab("chrome://downloads/")
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

                    MenuItem {
                        text: "History"
                        onTriggered: Browser.newTab("chrome://history/")
                    }

                    MenuItem {
                        text: qsTr("Extensions")
                        visible: Browser.chromeStyle
                        onTriggered: Browser.newTab("chrome://extensions")
                    }

                    MenuItem {
                        text: qsTr("Browser Settings…")
                        visible: Browser.chromeStyle
                        onTriggered: Browser.newTab("chrome://settings/")
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



    // the folder whose title is being edited in place
    property string renamingId: ""

    function startRename(id) {
        if (!id)
            return;
        root.renamingId = id;
        Qt.callLater(() => {
            const i = Browser.sidebar.rowOf(id);
            if (i >= 0)
                tabList.positionViewAtIndex(i, ListView.Contain);
        });
    }

    function newFolder(parentId) {
        root.startRename(Browser.sidebar.createFolder(parentId || ""));
    }

    // menus act on a snapshot: the row can scroll away or be reused meanwhile
    function openTabMenu(m) {
        tabMenu.target = {
            nodeId: m.nodeId,
            title: m.title || "",
            url: m.url ? m.url.toString() : "",
            iconUrl: m.iconUrl || "",
            inFolder: m.inFolder === true,
            parentId: m.parentId || "",
            tabIndex: m.tabIndex
        };
        tabMenu.folders = Browser.sidebar.folders();
        tabMenu.popup();
    }

    function openFolderMenu(m) {
        folderMenu.target = {
            nodeId: m.nodeId,
            title: m.title || "",
            tabCount: m.tabCount || 0
        };
        folderMenu.popup();
    }

    // right-click on empty sidebar space
    Menu {
        id: sidebarMenu
        popupType: Popup.Native

        MenuItem {
            text: qsTr("New Tab")
            onTriggered: root.commandBarRequested("new")
        }
        MenuItem {
            text: qsTr("New Folder")
            onTriggered: root.newFolder()
        }
    }

    Menu {
        id: tabMenu
        popupType: Popup.Native

        property var target: ({})
        property var folders: []
        readonly property bool isPage: (target.url || "") !== "" && target.url !== "newtab://newtab"
        readonly property bool bookmarked: Bookmarks.count >= 0 && isPage && Bookmarks.isBookmarked(target.url)

        MenuItem {
            text: qsTr("Copy Link")
            enabled: tabMenu.isPage
            onTriggered: Browser.sidebar.copyLink(tabMenu.target.nodeId)
        }
        MenuItem {
            text: tabMenu.bookmarked ? qsTr("Remove Bookmark") : qsTr("Bookmark")
            enabled: tabMenu.isPage
            onTriggered: Bookmarks.toggleBookmark(tabMenu.target.title, tabMenu.target.url, tabMenu.target.iconUrl)
        }
        MenuItem {
            text: qsTr("Duplicate Tab")
            enabled: tabMenu.isPage
            onTriggered: Browser.newTab(tabMenu.target.url)
        }

        MenuSeparator {}

        Menu {
            id: addToFolderMenu
            title: tabMenu.target.inFolder ? qsTr("Move to Folder") : qsTr("Add to Folder")

            MenuItem {
                text: qsTr("New Folder")
                onTriggered: root.startRename(Browser.sidebar.moveToNewFolder(tabMenu.target.nodeId))
            }
            MenuSeparator {}

            Instantiator {
                model: tabMenu.folders
                delegate: MenuItem {
                    required property var modelData
                    text: "    ".repeat(modelData.depth) + (modelData.icon ? modelData.icon + "  " : "") + modelData.title
                    // already there
                    enabled: modelData.id !== tabMenu.target.parentId
                    onTriggered: Browser.sidebar.addToFolder(tabMenu.target.nodeId, modelData.id)
                }
                // after "New Folder" and the separator
                onObjectAdded: (index, object) => addToFolderMenu.insertItem(index + 2, object)
                onObjectRemoved: (index, object) => addToFolderMenu.removeItem(object)
            }
        }

        MenuItem {
            text: qsTr("Remove from Folder")
            visible: tabMenu.target.inFolder === true
            onTriggered: Browser.sidebar.removeFromFolder(tabMenu.target.nodeId)
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("Close Tab")
            onTriggered: Browser.closeTab(tabMenu.target.tabIndex)
        }
    }

    Menu {
        id: folderMenu
        popupType: Popup.Native

        property var target: ({})

        MenuItem {
            text: qsTr("Rename")
            onTriggered: root.startRename(folderMenu.target.nodeId)
        }

        Menu {
            id: iconMenu
            title: qsTr("Change Icon")

            MenuItem {
                text: qsTr("Folder")
                onTriggered: Browser.sidebar.setFolderIcon(folderMenu.target.nodeId, "")
            }
            MenuSeparator {}

            Instantiator {
                model: ["⭐", "💼", "🏠", "📚", "🎵", "🎮", "🛒", "💡", "🔧", "📰", "✈️", "🎨", "💻", "📌", "❤️", "🔥"]
                delegate: MenuItem {
                    required property string modelData
                    text: modelData
                    onTriggered: Browser.sidebar.setFolderIcon(folderMenu.target.nodeId, modelData)
                }
                onObjectAdded: (index, object) => iconMenu.insertItem(index + 2, object)
                onObjectRemoved: (index, object) => iconMenu.removeItem(object)
            }
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("New Tab in Folder")
            onTriggered: Browser.sidebar.newTabInFolder(folderMenu.target.nodeId)
        }
        MenuItem {
            text: qsTr("New Subfolder")
            onTriggered: root.newFolder(folderMenu.target.nodeId)
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("Expand All")
            onTriggered: Browser.sidebar.setExpanded(folderMenu.target.nodeId, true, true)
        }
        MenuItem {
            text: qsTr("Collapse All")
            onTriggered: Browser.sidebar.setExpanded(folderMenu.target.nodeId, false, true)
        }
        MenuItem {
            text: qsTr("Close All Tabs")
            enabled: folderMenu.target.tabCount > 0
            onTriggered: Browser.sidebar.closeFolderTabs(folderMenu.target.nodeId)
        }

        MenuSeparator {}

        MenuItem {
            text: folderMenu.target.tabCount > 0 ? qsTr("Delete Folder…") : qsTr("Delete Folder")
            onTriggered: {
                if (folderMenu.target.tabCount > 0) {
                    deleteFolderPopup.target = folderMenu.target;
                    deleteFolderPopup.open();
                } else {
                    Browser.sidebar.deleteNode(folderMenu.target.nodeId);
                }
            }
        }
    }

    // a folder with tabs in it asks what happens to them
    Popup {
        id: deleteFolderPopup
        property var target: ({})

        parent: Overlay.overlay
        modal: true
        focus: true
        padding: 20
        width: Math.min(300, parent ? parent.width - 32 : 300)
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        background: Rectangle {
            radius: 16
            color: Theme.bg
            border.color: Theme.border
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: qsTr("Delete \"%1\"?").arg(deleteFolderPopup.target.title || "")
                textFormat: Text.PlainText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: deleteFolderPopup.target.tabCount === 1
                    ? qsTr("It holds 1 tab. Keep it open, or close it too?")
                    : qsTr("It holds %1 tabs. Keep them open, or close them too?").arg(deleteFolderPopup.target.tabCount || 0)
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                PillButton {
                    text: qsTr("Cancel")
                    textColor: Theme.textMuted
                    fillColor: Theme.surfaceHigh
                    hoverFillColor: Theme.surface
                    onClicked: deleteFolderPopup.close()
                }
                PillButton {
                    text: qsTr("Keep Tabs")
                    textColor: Theme.text
                    fillColor: Theme.surfaceHigh
                    hoverFillColor: Theme.surface
                    onClicked: {
                        Browser.sidebar.deleteNode(deleteFolderPopup.target.nodeId, true);
                        deleteFolderPopup.close();
                    }
                }
                PillButton {
                    text: qsTr("Close Tabs")
                    textColor: "white"
                    fillColor: Theme.danger
                    hoverFillColor: Qt.darker(Theme.danger, 1.1)
                    onClicked: {
                        Browser.sidebar.deleteNode(deleteFolderPopup.target.nodeId, false);
                        deleteFolderPopup.close();
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
