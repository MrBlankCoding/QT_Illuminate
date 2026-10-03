import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

Popup {
    id: root

    property var webView: null
    readonly property real minZoom: 0.25
    readonly property real maxZoom: 5.0
    readonly property int zoomPercent: webView ? Math.round(webView.zoomFactor * 100) : 100

    popupType: Popup.Window
    modal: false
    focus: false
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: row.implicitWidth + 14
    height: 30
    x: parent.width - width - 16
    y: parent.height - height - 16
    visible: webView && zoomPercent !== 100

    function zoomBy(delta) {
        if (!webView)
            return;
        webView.zoomFactor = Math.min(maxZoom, Math.max(minZoom, webView.zoomFactor + delta));
    }

    function zoomReset() {
        if (webView)
            webView.zoomFactor = 1.0;
    }

    background: Rectangle {
        radius: height / 2
        color: Theme.surface
        border.color: Theme.border
        border.width: 1
    }

    contentItem: RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 7
        anchors.rightMargin: 7
        spacing: 6

        LucideIcon {
            objectName: "zoomOutButton"
            size: 13
            source: "qrc:/QT_Illuminate/ui/ui/icons/minus.svg"
            color: zoomOutHover.hovered ? Theme.text : Theme.textMuted
            Layout.alignment: Qt.AlignVCenter

            HoverHandler {
                id: zoomOutHover
            }
            TapHandler {
                onTapped: root.zoomBy(-0.1)
            }
        }

        Text {
            objectName: "zoomResetButton"
            text: root.zoomPercent + "%"
            color: resetHover.hovered ? Theme.text : Theme.textMuted
            font.pixelSize: Theme.fontSizeS
            font.family: Theme.fontFamily
            Layout.preferredWidth: 30
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            HoverHandler {
                id: resetHover
            }
            TapHandler {
                onTapped: root.zoomReset()
            }
        }

        LucideIcon {
            objectName: "zoomInButton"
            size: 13
            source: "qrc:/QT_Illuminate/ui/ui/icons/plus.svg"
            color: zoomInHover.hovered ? Theme.text : Theme.textMuted
            Layout.alignment: Qt.AlignVCenter

            HoverHandler {
                id: zoomInHover
            }
            TapHandler {
                onTapped: root.zoomBy(0.1)
            }
        }
    }
}
