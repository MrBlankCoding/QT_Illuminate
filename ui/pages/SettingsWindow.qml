import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

ApplicationWindow {
    id: root
    width: 520
    height: 480
    minimumWidth: 420
    minimumHeight: 360
    title: "Settings"
    readonly property bool frameless: Qt.platform.os !== "osx"
    flags: frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window

    component DragHeader: Item {
        DragHandler {
            target: null
            onActiveChanged: {
                if (active)
                    root.startSystemMove()
            }
        }
        TapHandler {
            gesturePolicy: TapHandler.DragThreshold
            onTapCountChanged: {
                if (tapCount !== 2)
                    return
                root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
            }
        }
    }

    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.tabBarHeight
        visible: root.frameless
        color: Theme.tabStripBg

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.border
        }

        DragHeader {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: controls.left
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "Settings"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
            font.weight: Font.Medium
        }

        WindowControls {
            id: controls
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
        }
    }

    // header is collapsed (height 0) on macOS, so this still aligns to the top
    ScrollView {
        id: scroll
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: availableWidth

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 10

            Item {
                Layout.preferredHeight: 6
            }

            Item {
                Layout.preferredHeight: 14
            }
        }
    }

    ResizeGrips {
        anchors.fill: parent
        visible: root.frameless && root.visibility === Window.Windowed
        z: 1000
        onRequestSystemResize: edges => root.startSystemResize(edges)
    }
}
