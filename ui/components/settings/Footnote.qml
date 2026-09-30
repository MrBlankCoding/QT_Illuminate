import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

// muted, wrapping explanation that trails a group of settings. Must sit in a layout.
Text {
    Layout.fillWidth: true
    Layout.leftMargin: 4
    Layout.rightMargin: 4
    color: Theme.textMuted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeS
    wrapMode: Text.WordWrap
}
