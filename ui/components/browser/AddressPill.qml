import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

Item {
    id: root

    property string currentUrl: ""
    property bool isLoading: false
    property int loadProgress: 0

    readonly property bool isBookmarked: Bookmarks.count >= 0 && root.currentUrl !== "" && Bookmarks.isBookmarked(root.currentUrl)
    signal clicked
    signal toggleBookmark

    implicitHeight: 32
    scale: tap.pressed ? Theme.pressScale : 1
    Behavior on scale { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic } }

    // "https://www.example.com/a/b" -> "example.com"
    function displayHost(url) {
        const m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)/i.exec(url);
        return m ? m[1].replace(/^www\./, "") : url;
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusItem
        color: hover.hovered ? Theme.itemHover : Theme.fieldBg
        clip: true
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space3 - 2
            anchors.rightMargin: Theme.space2
            spacing: Theme.space2 - 2

            LucideIcon {
                size: 13
                Layout.alignment: Qt.AlignVCenter
                source: root.currentUrl === "" ? "qrc:/QT_Illuminate/ui/ui/icons/search.svg"
                      : root.currentUrl.startsWith("https://") ? "qrc:/QT_Illuminate/ui/ui/icons/lock.svg"
                      : root.currentUrl.startsWith("http://") ? "qrc:/QT_Illuminate/ui/ui/icons/alert-triangle.svg"
                      : "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                color: root.currentUrl.startsWith("http://") ? Theme.danger : Theme.textMuted
            }

            Text {
                Layout.fillWidth: true
                text: root.currentUrl === "" ? "Search with " + Prefs.searchEngineName + " or enter address"
                                             : root.displayHost(root.currentUrl)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.currentUrl === "" ? Theme.textMuted : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
            }

            LucideIcon {
                size: 13
                Layout.alignment: Qt.AlignVCenter
                visible: root.currentUrl !== "" && (hover.hovered || root.isBookmarked)
                source: root.isBookmarked ? "qrc:/QT_Illuminate/ui/ui/icons/star-filled.svg" : "qrc:/QT_Illuminate/ui/ui/icons/star.svg"
                color: root.isBookmarked ? Theme.accent : (starHover.hovered ? Theme.text : Theme.textMuted)

                HoverHandler {
                    id: starHover
                }
                TapHandler {
                    onTapped: root.toggleBookmark()
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            height: Theme.progressH
            width: parent.width * (root.loadProgress / 100)
            color: Theme.accent
            opacity: root.isLoading && root.loadProgress > 0 && root.loadProgress < 100 ? 1 : 0
            Behavior on width { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
            Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: tap
        // the star's own tap reaches this handler too
        onTapped: if (!starHover.hovered) root.clicked()
    }
}
