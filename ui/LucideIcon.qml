import QtQuick
import QtQuick.Effects
import QT_Illuminate.ui

// render icons as any color
Item {
    id: root

    property string source: ""
    property color  color:  Theme.textMuted
    property int    size:   16

    width:  size
    height: size

    Image {
        id: img
        anchors.fill: parent
        source:       root.source
        visible:      false
        fillMode:     Image.PreserveAspectFit
        smooth:       true
        mipmap:       true
    }

    MultiEffect {
        anchors.fill:      parent
        source:            img
        colorization:      1.0
        colorizationColor: root.color

        Behavior on colorizationColor {
            ColorAnimation { duration: Theme.durationFast }
        }
    }
}
