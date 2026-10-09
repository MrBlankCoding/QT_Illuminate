import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: tree
    property var sidebar

    // exposed so the sidebar's startRename() can scroll a renamed row into view
    property alias tabList: tabList
    signal contextMenuRequested

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
        repeat: true
        interval: 16
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
                    onContextMenuRequested: sidebar.openTabMenu(row.model)
                }
            }

            Component {
                id: folderComponent
                FolderRow {
                    title: row.model.title ?? ""
                    icon: row.model.icon ?? ""
                    expanded: row.expanded
                    editing: sidebar.renamingId !== "" && sidebar.renamingId === row.nodeId
                    dragging: tree.dragId === row.nodeId
                    dropTarget: tree.dropTargetId === row.nodeId && tree.dropPosition === SidebarModel.Into
                    onToggled: Browser.sidebar.toggleFolder(row.nodeId)
                    onRenameRequested: sidebar.renamingId = row.nodeId
                    onRenamed: title => {
                        Browser.sidebar.renameFolder(row.nodeId, title);
                        sidebar.renamingId = "";
                    }
                    onEditingCanceled: sidebar.renamingId = ""
                    onMenuRequested: sidebar.openFolderMenu(row.model)
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
                            onTapped: sidebar.commandBarRequested("new")
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: tree.contextMenuRequested()
                        }
                    }
                }
            }

            DragHandler {
                id: dragHandler
                target: null
                enabled: (row.kind === "tab" || row.kind === "folder") && sidebar.renamingId !== row.nodeId
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
                    sidebar.commandBarRequested("new");
            }
        }

        // empty space: the sidebar's own menu
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: eventPoint => {
                const p = eventPoint.position;
                if (!tabList.itemAt(p.x + tabList.contentX, p.y + tabList.contentY))
                    tree.contextMenuRequested();
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
