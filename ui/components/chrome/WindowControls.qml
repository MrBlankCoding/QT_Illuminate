import QtQuick
import QtQuick.Window
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// minimise / maximise / close for frameless windows (Windows, Linux)
Row {
    id: root

    // the window to control; differs from root.Window inside the sidebar overlay
    property var targetWindow: root.Window.window
    readonly property bool isMaximized: targetWindow ? targetWindow.visibility === Window.Maximized : false
    property int buttonHeight: Theme.titleBarHeight
    property int buttonWidth: Theme.sysControlW

    component ControlButton: Item {
        id: button
        property url iconSource
        property int iconSize: 14
        property color hoverColor: Theme.surfaceHigh
        property color hoverIconColor: Theme.text
        signal clicked

        width: root.buttonWidth
        height: root.buttonHeight

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
        iconSource: "qrc:/QT_Illuminate/ui/icons/minus.svg"
        onClicked: root.targetWindow.showMinimized()
    }

    ControlButton {
        // overlapping squares = "restore down" while maximised
        iconSource: root.isMaximized ? "qrc:/QT_Illuminate/ui/icons/copy.svg" : "qrc:/QT_Illuminate/ui/icons/square.svg"
        iconSize: root.isMaximized ? 13 : 12
        onClicked: root.isMaximized ? root.targetWindow.showNormal() : root.targetWindow.showMaximized()
    }

    ControlButton {
        iconSource: "qrc:/QT_Illuminate/ui/icons/x.svg"
        iconSize: 15
        hoverColor: "#e81123"
        hoverIconColor: "white"
        onClicked: root.targetWindow.close()
    }
}
