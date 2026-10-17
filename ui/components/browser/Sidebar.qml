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
    property bool overlay: false
    property var targetWindow: root.Window.window
    readonly property bool currentBookmarked: addressPill.isBookmarked

    signal openSettings
    signal commandBarRequested(string mode)   // "new" | "edit"
    signal toggleCollapsed

    function openSpaceEditor(space) {
        if (spaceEditorPopup)
            spaceEditorPopup.openFor(space)
    }

    function confirmDeleteSpace(space) {
        if (deleteSpacePopup && space)
            deleteSpacePopup.openFor(space)
    }

    readonly property bool isFullScreen: root.targetWindow ? root.targetWindow.visibility === Window.FullScreen : false
    readonly property bool customWindowControls: !Theme.isMac && !isFullScreen
    readonly property bool menuOpen: footer.popupsOpen || sideMenus.popupsOpen || renamingId !== ""

    implicitWidth: Prefs.sidebarWidth

    function toggleBookmark() {
        if (root.currentUrl === "")
            return;
        Bookmarks.toggleBookmark(root.currentTitle, root.currentUrl, root.currentIconUrl);
    }



    // the folder whose title is being edited in place
    property string renamingId: ""

    function startRename(id) {
        if (!id)
            return;
        if (root.targetWindow && root.targetWindow.claimUiFocus)
            root.targetWindow.claimUiFocus("sidebarRename");
        root.renamingId = id;
        Qt.callLater(() => {
            const i = Browser.sidebar.rowOf(id);
            if (i >= 0) {
                treeView.tabList.positionViewAtIndex(i, ListView.Contain);
                // The delegate may be created only after scrolling lays out the
                // newly inserted row, so focus it after that layout turn.
                Qt.callLater(() => {
                    const row = treeView.tabList.itemAtIndex(i);
                    if (row && row.focusTitle)
                        row.focusTitle();
                });
            }
        });
    }

    function newFolder(parentId) {
        root.startRename(Browser.sidebar.createFolder(parentId || ""));
    }

    // menus act on a snapshot: the row can scroll away or be reused meanwhile
    function openTabMenu(m) {
        sideMenus.tabMenu.target = {
            nodeId: m.nodeId,
            title: m.title || "",
            url: m.url ? m.url.toString() : "",
            iconUrl: m.iconUrl || "",
            inFolder: m.inFolder === true,
            parentId: m.parentId || "",
            tabIndex: m.tabIndex
        };
        sideMenus.tabMenu.folders = Browser.sidebar.folders();
        sideMenus.tabMenu.popup();
    }

    function openFolderMenu(m) {
        sideMenus.folderMenu.target = {
            nodeId: m.nodeId,
            title: m.title || "",
            tabCount: m.tabCount || 0
        };
        sideMenus.folderMenu.popup();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.sidebarPadding
        // the card's own margin is the gap on the right
        anchors.rightMargin: root.overlay ? Theme.sidebarPadding : 0
        anchors.bottomMargin: Theme.sidebarPadding
        spacing: Theme.space2

        SidebarTitleStrip {
            sidebar: root
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

        SidebarTree {
            id: treeView
            sidebar: root
            onContextMenuRequested: sideMenus.sidebarMenu.popup()
        }

        // Downloads, space switcher, and creation menu stay docked at the bottom.
        SidebarFooter {
            id: footer
            sidebar: root
        }
    }

    // creating or editing a space; "editing" carries the space being changed
    Popup {
        id: spaceEditorPopup
        property var target: null
        readonly property bool creating: target === null

        parent: Overlay.overlay
        modal: true
        focus: true
        Component.onCompleted: PopupCloser.watch(spaceEditorPopup)
        padding: 24
        width: Math.min(360, parent ? parent.width - 32 : 360)
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: {
            if (root.targetWindow && root.targetWindow.claimUiFocus)
                root.targetWindow.claimUiFocus("spaceEditor");
            Qt.callLater(function() { spaceEditor.focusName() });
        }
        onClosed: {
            if (root.targetWindow && root.targetWindow.releaseUiFocus)
                root.targetWindow.releaseUiFocus("spaceEditor");
        }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        background: Rectangle {
            radius: 18
            color: Theme.surfaceHigh
            border.color: Theme.border
            border.width: 1
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 200; easing.type: Easing.OutCubic }
        }

        contentItem: ColumnLayout {
            spacing: 18

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: spaceEditorPopup.creating ? qsTr("Create a space") : qsTr("Edit space")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXL
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: spaceEditorPopup.creating
                          ? qsTr("Give this space a name and a colour.")
                          : qsTr("Make this space easy to recognize.")
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeS
                    wrapMode: Text.WordWrap
                }
            }

            SpaceEditor {
                id: spaceEditor
                Layout.fillWidth: true
                onAccepted: spaceEditorPopup.commit()
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
                    onClicked: spaceEditorPopup.close()
                }
                PillButton {
                    text: spaceEditorPopup.creating ? qsTr("Create") : qsTr("Save")
                    textColor: Theme.onAccent
                    fillColor: Theme.accent
                    hoverFillColor: Qt.darker(Theme.accent, 1.1)
                    enabled: spaceEditor.trimmedName.length > 0
                    onClicked: spaceEditorPopup.commit()
                }
            }
        }

        function openFor(space) {
            target = space || null;
            spaceEditor.name = space ? space.name : "";
            spaceEditor.selectedColor = space ? space.color : Spaces.nextSpaceColor();
            open();
        }

        // an empty name would leave an unidentifiable space, so it is refused
        function commit() {
            const name = spaceEditor.trimmedName;
            if (name.length === 0) {
                spaceEditor.focusName();
                return;
            }
            if (spaceEditorPopup.creating) {
                const created = Spaces.createSpace(name, spaceEditor.selectedColor);
                if (created)
                    Spaces.activeSpace = created;
            } else if (spaceEditorPopup.target) {
                spaceEditorPopup.target.name = name;
                spaceEditorPopup.target.color = spaceEditor.selectedColor;
            }
            close();
        }
    }

    // a space takes its tabs with it when it goes
    Popup {
        id: deleteSpacePopup
        property var target: null

        function openFor(space) {
            target = space
            open()
        }

        parent: Overlay.overlay
        modal: true
        focus: true
        Component.onCompleted: PopupCloser.watch(deleteSpacePopup)
        padding: 24
        width: Math.min(340, parent ? parent.width - 32 : 340)
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        background: Rectangle {
            radius: 18
            color: Theme.surfaceHigh
            border.color: Theme.border
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: 13
                    color: deleteSpacePopup.target ? deleteSpacePopup.target.color : Theme.danger
                    Text {
                        anchors.centerIn: parent
                        text: deleteSpacePopup.target ? deleteSpacePopup.target.initial : "?"
                        color: Theme.luma(parent.color) > 0.55 ? "#1e1e2e" : "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Delete space?")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXL
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: deleteSpacePopup.target ? deleteSpacePopup.target.name : ""
                        textFormat: Text.PlainText
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                        elide: Text.ElideRight
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: qsTr("Its folders, tabs and bookmarks go with it. Logins, cookies and history stay.")
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
                    onClicked: deleteSpacePopup.close()
                }
                PillButton {
                    text: qsTr("Delete Space")
                    textColor: "white"
                    fillColor: Theme.danger
                    hoverFillColor: Qt.darker(Theme.danger, 1.1)
                    onClicked: {
                        Spaces.deleteSpace(deleteSpacePopup.target);
                        deleteSpacePopup.close();
                    }
                }
            }
        }
    }

    // the sidebar's context menus (right-click on empty space, row, and folder)
    SidebarMenus {
        id: sideMenus
        sidebar: root
    }

    Connections {
        target: sideMenus.tabMenu
        function onOpened() {
            if (root.targetWindow && root.targetWindow.raiseActiveWebView)
                Qt.callLater(() => root.targetWindow.raiseActiveWebView());
        }
        function onClosed() {
            if (root.targetWindow && root.targetWindow.raiseActiveWebView)
                Qt.callLater(() => root.targetWindow.raiseActiveWebView());
        }
    }

    // a two-finger swipe sideways anywhere in the sidebar moves one space over;
    // sits on top but lets every wheel event through to the list below
    Item {
        anchors.fill: parent
        z: 5

        WheelHandler {
            target: null
            blocking: false
            enabled: !root.menuOpen && Spaces.spaces.length > 1

            property real travelX: 0
            property real travelY: 0
            property bool spent: false

            onWheel: event => {
                // mouse wheels have no phase: only trackpad gestures count
                if (event.phase === Qt.NoScrollPhase || event.phase === Qt.ScrollMomentum)
                    return;
                if (event.phase === Qt.ScrollBegin) {
                    travelX = 0;
                    travelY = 0;
                    spent = false;
                    return;
                }
                if (spent)
                    return;

                // deltas follow the content; flip them back to the fingers
                const sign = event.inverted ? 1 : -1;
                travelX += sign * event.pixelDelta.x;
                travelY += Math.abs(event.pixelDelta.y);
                if (Math.abs(travelX) < 60 || Math.abs(travelX) < travelY * 2)
                    return;

                spent = true;
                const spaces = Spaces.spaces;
                const next = spaces.indexOf(Spaces.activeSpace) + (travelX < 0 ? 1 : -1);
                if (next >= 0 && next < spaces.length)
                    Spaces.activeSpace = spaces[next];
            }
        }
    }

}
