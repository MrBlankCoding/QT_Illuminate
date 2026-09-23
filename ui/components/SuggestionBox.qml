import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Rectangle {
    id: root

    property var model: null
    property int highlighted: -1
    property bool addressFocused: false
    signal suggestionClicked(int index)

    height: model.count > 0 ? (suggestionsColumn.implicitHeight + 8) : 0
    visible: model.count > 0 && addressFocused
    z: 200
    radius: 8
    color: Theme.surface
    border.color: Theme.border
    border.width: 1
    opacity: visible ? 1 : 0
    Behavior on height {
        NumberAnimation {
            duration: Theme.durationFast
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.durationFast
        }
    }

    Column {
        id: suggestionsColumn
        width: parent.width
        anchors.top: parent.top

        Repeater {
            model: root.model

            delegate: Rectangle {
                required property int index
                required property var model
                objectName: "suggestionRow"
                width: suggestionsColumn.width
                height: 32
                radius: 6
                color: index === root.highlighted ? Theme.surfaceHigh : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    LucideIcon {
                        size: 14
                        source: model.isBookmark ? "qrc:/QT_Illuminate/ui/ui/icons/star-filled.svg" : "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                        color: model.isBookmark ? Theme.accent : Theme.textMuted
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        Layout.fillWidth: true
                        text: model.text
                        color: Theme.text
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                HoverHandler {
                    onHoveredChanged: if (hovered)
                        root.highlighted = index
                }
                TapHandler {
                    onTapped: root.suggestionClicked(index)
                }
            }
        }
    }
}
