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
    property string dragSplitMemberId: ""
    property string dragSplitMemberTitle: ""
    property string dragSplitMemberIcon: ""
    property point dragSplitPosition: Qt.point(0, 0)
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

    function isBlankPlaceholder(url) {
        return !url || url.toString() === "" || url.toString() === "newtab://newtab";
    }

    function dragMove(scenePos) {
        const p = tree.mapFromItem(null, scenePos.x, scenePos.y);
        tree.dragY = p.y;
        const edge = Theme.tabRowHeight;
        scrollTimer.direction = p.y < edge ? -1 : p.y > tree.height - edge ? 1 : 0;
        tree.updateTarget();
    }

    // itemAt() returns QQuickItem, while row delegates provide these fields.
    // qmllint disable missing-property
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
        if (!item || !item["nodeId"]) {
            tree.clearTarget();
            return;
        }

        const nodeId = item["nodeId"];
        const kind = item["kind"];
        const expanded = item["expanded"];
        const indent = item["indent"];
        const frac = Math.max(0, Math.min(1, (cy - item.y) / item.height));
        let pos;
        if (kind === "folder")
            pos = frac < 0.25 ? SidebarModel.Before
                : frac > 0.75 && !expanded ? SidebarModel.After
                : SidebarModel.Into;
        else if (tree.dragKind === "tab" && kind === "tab" && frac >= 0.25 && frac <= 0.75)
            pos = SidebarModel.Into;
        else
            pos = frac < 0.5 ? SidebarModel.Before : SidebarModel.After;

        if (!Browser.sidebar.canDrop(tree.dragId, nodeId, pos)) {
            tree.clearTarget();
            return;
        }
        if (nodeId !== tree.dropTargetId || pos !== tree.dropPosition) {
            tree.dropTargetId = nodeId;
            tree.dropPosition = pos;
            if (pos === SidebarModel.Into && kind === "folder" && !expanded)
                expandTimer.restart();
            else
                expandTimer.stop();
        }
        const gap = tabList.spacing / 2;
        tree.indicatorX = indent;
        tree.indicatorY = pos === SidebarModel.Before ? item.y - gap : item.y + item.height + gap;
    }
    // qmllint enable missing-property

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
        interactive: tree.dragId === "" && tree.dragSplitMemberId === ""
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
                ? (Browser.sidebar.folderCount > 0 ? Theme.space2 + 1 : 0)
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
                               : row.kind === "split" ? splitComponent
                               : row.kind === "tab" ? tabComponent
                               : row.kind === "header" ? headerComponent
                               : null
            }

            Rectangle {
                anchors.fill: parent
                z: 4
                visible: row.kind === "tab" && tree.dragKind === "tab"
                    && tree.dropTargetId === row.nodeId && tree.dropPosition === SidebarModel.Into
                radius: Theme.radiusTab
                color: Qt.alpha(Theme.accent, 0.17)
                border.color: Theme.accent
                border.width: 1
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        Layout.preferredWidth: 27
                        Layout.preferredHeight: 18
                        radius: 4
                        color: "transparent"
                        border.color: Theme.accent
                        border.width: 1
                        Row {
                            anchors.fill: parent
                            anchors.margins: 2
                            spacing: 2
                            Rectangle { width: (parent.width - parent.spacing) / 2; height: parent.height; radius: 2; color: Theme.accent }
                            Rectangle { width: (parent.width - parent.spacing) / 2; height: parent.height; radius: 2; color: Theme.accent }
                        }
                    }
                    Text {
                        text: qsTr("Release to split")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                        font.weight: Font.Medium
                    }
                }
            }

            Component {
                id: tabComponent
                TabItem {
                    model: row.model
                    index: row.index
                    isActive: row.model.active === true
                    dragging: tree.dragId === row.nodeId
                    onActivated: {
                        if (!tree.isBlankPlaceholder(row.model.url))
                            Browser.activateTab(row.model.tabIndex);
                    }
                    onCloseClicked: Browser.closeTab(row.model.tabIndex)
                    onContextMenuRequested: tree.sidebar.openTabMenu(row.model)
                }
            }

            Component {
                id: folderComponent
                FolderRow {
                    title: row.model.title ?? ""
                    icon: row.model.icon ?? ""
                    expanded: row.expanded
                    editing: tree.sidebar.renamingId !== "" && tree.sidebar.renamingId === row.nodeId
                    dragging: tree.dragId === row.nodeId
                    dropTarget: tree.dropTargetId === row.nodeId && tree.dropPosition === SidebarModel.Into
                    onToggled: Browser.sidebar.toggleFolder(row.nodeId)
                    onRenameRequested: tree.sidebar.startRename(row.nodeId)
                    onRenamed: title => {
                        Browser.sidebar.renameFolder(row.nodeId, title);
                        tree.sidebar.renamingId = "";
                        if (tree.sidebar.targetWindow && tree.sidebar.targetWindow.releaseUiFocus)
                            tree.sidebar.targetWindow.releaseUiFocus("sidebarRename");
                    }
                    onEditingCanceled: {
                        tree.sidebar.renamingId = "";
                        if (tree.sidebar.targetWindow && tree.sidebar.targetWindow.releaseUiFocus)
                            tree.sidebar.targetWindow.releaseUiFocus("sidebarRename");
                    }
                    onMenuRequested: tree.sidebar.openFolderMenu(row.model)
                }
            }

            Component {
                id: splitComponent
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusTab
                    color: row.model.active ? Theme.itemActive : Theme.itemHover
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space2
                        spacing: Theme.space1
                        Repeater {
                            model: row.model.splitMembers || []
                            delegate: Item {
                                id: splitMember
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumWidth: 0
                                property bool faviconFailed: false
                                readonly property string memberIconUrl: modelData.iconUrl || ""
                                onMemberIconUrlChanged: faviconFailed = false

                                readonly property bool memberActive: modelData.active === true
                                readonly property bool memberHovered: memberHover.hovered
                                readonly property bool memberDragging: tree.dragSplitMemberId === modelData.id

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radiusS
                                    color: parent.memberDragging ? Qt.alpha(Theme.accent, 0.28)
                                         : parent.memberActive ? Qt.alpha(Theme.accent, 0.16)
                                         : parent.memberHovered ? Theme.itemHover : "transparent"
                                    border.width: parent.memberActive || parent.memberDragging ? 1 : 0
                                    border.color: Qt.alpha(Theme.accent, 0.48)
                                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                                }

                                HoverHandler { id: memberHover }

                                TapHandler {
                                    onTapped: {
                                        for (let i = 0; i < Browser.tabModel.count; ++i) {
                                            const tab = Browser.tabModel.tabAt(i);
                                            if (tab && tab.id === splitMember.modelData.id && !tree.isBlankPlaceholder(tab.url)) {
                                                Browser.activateTab(i);
                                                break;
                                            }
                                        }
                                    }
                                }

                                DragHandler {
                                    target: null
                                    onActiveChanged: {
                                        if (active) {
                                            tree.dragSplitMemberId = splitMember.modelData.id;
                                            tree.dragSplitMemberTitle = splitMember.modelData.title;
                                            tree.dragSplitMemberIcon = splitMember.modelData.iconUrl;
                                            const p = tree.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y);
                                            tree.dragSplitPosition = Qt.point(p.x + 14, p.y + 14);
                                        } else if (tree.dragSplitMemberId === splitMember.modelData.id) {
                                            const p = row.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y);
                                            const droppedOutside = p.x < 0 || p.y < 0 || p.x > row.width || p.y > row.height;
                                            tree.dragSplitMemberId = "";
                                            if (droppedOutside)
                                                Browser.sidebar.separateSplitTab(splitMember.modelData.id);
                                        }
                                    }
                                    onCentroidChanged: if (active) {
                                        const p = tree.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y);
                                        tree.dragSplitPosition = Qt.point(p.x + 14, p.y + 14);
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space1
                                    anchors.rightMargin: Theme.space1
                                    spacing: Theme.space1
                                    Rectangle {
                                        visible: row.index > 0
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 14
                                        color: Theme.itemActiveBorder
                                    }
                                    Item {
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        readonly property bool showMemberIcon: splitMember.memberIconUrl !== ""
                                            && !splitMember.memberIconUrl.startsWith("chrome:")
                                            && !splitMember.memberIconUrl.startsWith("about:")
                                            && !splitMember.faviconFailed
                                        Image {
                                            anchors.fill: parent
                                            visible: parent.showMemberIcon
                                            source: visible ? splitMember.memberIconUrl : ""
                                            sourceSize.width: 32
                                            sourceSize.height: 32
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            onStatusChanged: if (status === Image.Error) splitMember.faviconFailed = true
                                        }
                                        LucideIcon {
                                            anchors.centerIn: parent
                                            visible: !parent.showMemberIcon
                                            source: "qrc:/QT_Illuminate/ui/icons/globe.svg"
                                            size: 14
                                            color: Theme.textMuted
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: splitMember.modelData.title
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeS
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                        Text {
                            Layout.leftMargin: Theme.space1
                            text: "×"
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeM
                            TapHandler {
                                onTapped: Browser.sidebar.separateSplit(row.nodeId)
                            }
                        }
                    }
                }
            }

            // the divider under the folders, and "+ New Tab"
            Component {
                id: headerComponent
                Item {
                    Rectangle {
                        visible: Browser.sidebar.folderCount > 0
                        x: Theme.space2
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.space2 * 2
                        height: 1
                        color: Theme.itemHover
                    }
                }
            }

            DragHandler {
                id: dragHandler
                target: null
                enabled: (row.kind === "tab" || row.kind === "folder") && tree.sidebar.renamingId !== row.nodeId
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
            onTapped: eventPoint => {
                if (!tree.sidebar.renamingId)
                    return;
                const p = eventPoint.position;
                const row = tabList.itemAt(p.x + tabList.contentX, p.y + tabList.contentY);
                if (row && row.nodeId === tree.sidebar.renamingId)
                    return;
                tree.forceActiveFocus();
            }
        }

        TapHandler {
            onDoubleTapped: eventPoint => {
                const p = eventPoint.position;
                if (!tabList.itemAt(p.x + tabList.contentX, p.y + tabList.contentY))
                    tree.sidebar.commandBarRequested("new");
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

    SidebarDragPreviews {
        anchors.fill: parent
        tree: tree
    }

}
