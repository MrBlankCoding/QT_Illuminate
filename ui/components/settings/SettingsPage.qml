import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

// one pane of the settings window: a heading, an optional subtitle, then
// whatever the page puts in it. Must sit in a layout (or a StackLayout).
ColumnLayout {
    id: root
    property string heading
    property string subtitle
    spacing: 8

    Text {
        text: root.heading
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 24
        font.weight: Font.Bold
    }
    Text {
        visible: text.length > 0
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        text: root.subtitle
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeM
        wrapMode: Text.WordWrap
    }
}
