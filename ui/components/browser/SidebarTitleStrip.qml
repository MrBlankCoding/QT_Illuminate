import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: root

    property var sidebar

    Layout.fillWidth: true
    Layout.preferredHeight: Theme.titleBarHeight

    WindowDragRegion {
        anchors.fill: parent
        // it would move the overlay's own window
        enabled: !sidebar.overlay
    }

    RowLayout {
        anchors.fill: parent
        spacing: 2

        Item {
            visible: Theme.isMac && !sidebar.isFullScreen && !sidebar.overlay
            Layout.preferredWidth: Theme.trafficLightW - Theme.sidebarPadding
        }

        WindowControls {
            visible: sidebar.customWindowControls
            targetWindow: sidebar.targetWindow
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
            onClicked: sidebar.toggleCollapsed()
        }

        SidebarButton {
            icon: "qrc:/QT_Illuminate/ui/icons/chevron-left.svg"
            iconSize: 18
            enabled: sidebar.canGoBack
            onClicked: Browser.goBack()
        }
        SidebarButton {
            icon: "qrc:/QT_Illuminate/ui/icons/chevron-right.svg"
            iconSize: 18
            enabled: sidebar.canGoForward
            onClicked: Browser.goForward()
        }
        SidebarButton {
            icon: sidebar.isLoading ? "qrc:/QT_Illuminate/ui/icons/x.svg" : "qrc:/QT_Illuminate/ui/icons/rotate-cw.svg"
            iconSize: 15
            enabled: sidebar.currentUrl !== ""
            onClicked: Browser.reload()
        }
    }
}
