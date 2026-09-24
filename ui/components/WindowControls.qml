import QtQuick
import QtQuick.Window
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// minimise / maximise / close for frameless windows (Windows, Linux)
Row {
    id: root

    readonly property bool isMaximized: root.Window.visibility === Window.Maximized

    component ControlButton: Item {
        id: button
        property url iconSource
        property int iconSize: 14
        property color hoverColor: Theme.surfaceHigh
        property color hoverIconColor: Theme.text
        signal clicked

        width: Theme.sysControlW
        height: Theme.tabBarHeight

        Rectangle {
            anchors.fill: parent
            color: hover.hovered ? button.hoverColor : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: Theme.durationFast
                }
            }
        }

        LucideIcon {
            anchors.centerIn: parent
            source: button.iconSource
            size: button.iconSize
            color: hover.hovered ? button.hoverIconColor : Theme.textMuted
        }

        HoverHandler {
            id: hover
        }
        TapHandler {
            onTapped: button.clicked()
        }
    }

    ControlButton {
        iconSource: "qrc:/QT_Illuminate/ui/ui/icons/minus.svg"
        onClicked: root.Window.window.showMinimized()
    }

    ControlButton {
        iconSource: "qrc:/QT_Illuminate/ui/ui/icons/square.svg"
        iconSize: root.isMaximized ? 11 : 12
        onClicked: root.isMaximized ? root.Window.window.showNormal() : root.Window.window.showMaximized()
    }

    ControlButton {
        iconSource: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
        iconSize: 15
        hoverColor: "#e81123"
        hoverIconColor: "white"
        onClicked: root.Window.window.close()
    }
}
