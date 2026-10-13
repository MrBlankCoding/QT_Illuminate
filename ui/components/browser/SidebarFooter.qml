import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Qt.labs.folderlistmodel
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

RowLayout {
    id: root
    property var sidebar

    readonly property bool popupsOpen: addMenu.visible

    implicitHeight: Theme.iconButton
    Layout.fillWidth: true
    Layout.preferredHeight: Theme.iconButton
    Layout.minimumHeight: Theme.iconButton
    Layout.maximumHeight: Theme.iconButton
    Layout.alignment: Qt.AlignBottom
    spacing: 0

    FolderListModel {
        id: downloadsModel
        folder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        showFiles: true
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        nameFilters: ["*"]
    }

    Item {
        Layout.preferredWidth: 26
        Layout.fillHeight: true
        SidebarButton {
            anchors.centerIn: parent
            width: 26
            height: 28
            visible: downloadsModel.count > 0
            icon: "qrc:/QT_Illuminate/ui/icons/download.svg"
            iconSize: 18
            Accessible.name: qsTr("Downloads")
            onClicked: Browser.newTab("chrome://downloads/")
        }
    }

    Item {
        id: centerRail
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Theme.iconButton
        Layout.maximumHeight: Theme.iconButton

        SpaceSwitcher {
            anchors.centerIn: parent
            width: Math.min(160, Math.max(0, parent.width - 54))
            sidebar: root.sidebar
            onEditRequested: space => root.sidebar.openSpaceEditor(space)
            onDeleteRequested: space => root.sidebar.confirmDeleteSpace(space)
        }
    }

    SidebarButton {
        Layout.preferredWidth: 26
        Layout.preferredHeight: 28
        icon: "qrc:/QT_Illuminate/ui/icons/plus.svg"
        iconSize: 17
        active: addMenu.visible
        Accessible.name: qsTr("Create")
        onClicked: addMenu.popup()

        Menu {
            id: addMenu
            popupType: Popup.Native
            Component.onCompleted: PopupCloser.watch(addMenu)

            MenuItem {
                text: qsTr("New Tab")
                onTriggered: Browser.newTab()
            }
            MenuItem {
                text: qsTr("New Space…")
                onTriggered: root.sidebar.openSpaceEditor(null)
            }
            MenuSeparator {}
            MenuItem {
                text: qsTr("New Split")
                enabled: Browser.tabModel.activeIndex >= 0
                    && !Browser.sidebar.isSplitTab(Browser.tabModel.tabAt(Browser.tabModel.activeIndex).id)
                onTriggered: root.createSplit()
            }
        }
    }

    function createSplit() {
        const first = Browser.tabModel.tabAt(Browser.tabModel.activeIndex);
        if (!first || Browser.sidebar.isSplitTab(first.id))
            return;

        const count = Browser.tabModel.count;
        Browser.newTab("", true);
        if (Browser.tabModel.count !== count + 1)
            return;

        const second = Browser.tabModel.tabAt(Browser.tabModel.count - 1);
        if (second)
            Browser.sidebar.createSplit(first.id, second.id);
    }
}
