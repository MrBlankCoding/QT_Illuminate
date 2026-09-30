import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

// rounded surface that stacks SettingItems. Must sit in a layout.
Rectangle {
    id: root
    default property alias content: column.data

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight
    radius: 10
    color: Theme.surface

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
    }
}
