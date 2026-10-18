import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: root

    property var sidebar
    readonly property bool fullscreen: sidebar.isFullScreen

    Layout.fillWidth: true
    Layout.preferredHeight: Theme.titleBarHeight

    WindowDragRegion {
        anchors.fill: parent
        z: -1
        // it would move the overlay's own window
        enabled: !root.sidebar.overlay
    }

    RowLayout {
        anchors.fill: parent
        z: 1
        spacing: 2

        Item {
            visible: Theme.isMac && !root.sidebar.overlay
            Layout.preferredWidth: Theme.trafficLightW - Theme.sidebarPadding
        }

        SidebarButton {
            visible: root.fullscreen && Theme.isMac
            icon: "qrc:/QT_Illuminate/ui/icons/panel-left.svg"
            iconSize: 15
            onClicked: root.sidebar.toggleCollapsed()
        }

        WindowControls {
            visible: root.sidebar.customWindowControls
            targetWindow: root.sidebar.targetWindow
            buttonWidth: Theme.iconButton + 2
            buttonHeight: Theme.iconButton
            Layout.alignment: Qt.AlignVCenter
        }

        Item {
            Layout.fillWidth: true
        }

        SidebarButton {
            visible: !root.fullscreen || !Theme.isMac
            icon: "qrc:/QT_Illuminate/ui/icons/panel-left.svg"
            iconSize: 15
            onClicked: root.sidebar.toggleCollapsed()
        }

        SidebarButton {
            icon: "qrc:/QT_Illuminate/ui/icons/chevron-left.svg"
            iconSize: 18
            enabled: root.sidebar.canGoBack
            onClicked: Browser.goBack()
        }
        SidebarButton {
            icon: "qrc:/QT_Illuminate/ui/icons/chevron-right.svg"
            iconSize: 18
            enabled: root.sidebar.canGoForward
            onClicked: Browser.goForward()
        }
        SidebarButton {
            icon: root.sidebar.isLoading ? "qrc:/QT_Illuminate/ui/icons/x.svg" : "qrc:/QT_Illuminate/ui/icons/rotate-cw.svg"
            iconSize: 15
            enabled: root.sidebar.currentUrl !== ""
            onClicked: Browser.reload()
        }
    }
}
