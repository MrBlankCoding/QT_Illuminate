import QtQuick
import QT_Illuminate.ui

// window controls for mac and linux
// needs more testing
Item {
    id: root

    property string icon: ""
    property bool isClose: false
    property var action: function() {}

    width:  Theme.sysControlW
    height: parent ? parent.height : Theme.tabBarHeight

    Rectangle {
        anchors.fill: parent
        color: hover.hovered ? (root.isClose ? "#e81123" : Theme.surfaceHigh) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    LucideIcon {
        anchors.centerIn: parent
        source: root.icon
        size:   12
        color:  hover.hovered && root.isClose ? "#ffffff" : Theme.textMuted
    }

    HoverHandler { id: hover }
    TapHandler   { onTapped: root.action() }
}
