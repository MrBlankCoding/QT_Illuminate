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
    signal switchToProfile(var profile)
    signal openProfileSelector
    signal commandBarRequested(string mode)   // "new" | "edit"
    signal toggleCollapsed

    readonly property bool isFullScreen: root.targetWindow ? root.targetWindow.visibility === Window.FullScreen : false
    readonly property bool customWindowControls: !Theme.isMac && !isFullScreen
    readonly property bool menuOpen: footer.popupsOpen || sideMenus.popupsOpen || renamingId !== ""

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

    // the folder whose title is being edited in place
    property string renamingId: ""

    function startRename(id) {
        if (!id)
            return;
        root.renamingId = id;
        Qt.callLater(() => {
            const i = Browser.sidebar.rowOf(id);
            if (i >= 0)
                treeView.tabList.positionViewAtIndex(i, ListView.Contain);
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

        // folders, the "New Tab" header, then the tabs not in a folder
        SidebarTree {
            id: treeView
            sidebar: root
            onContextMenuRequested: sideMenus.sidebarMenu.popup()
        }

        // footer: profile, downloads, overflow menu
        SidebarFooter {
            id: footer
            sidebar: root
        }
    }

    // the sidebar's context menus (right-click on empty space, row, and folder)
    SidebarMenus {
        id: sideMenus
        sidebar: root
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
