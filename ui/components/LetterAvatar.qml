import QtQuick
import QT_Illuminate.ui

Rectangle {
    id: root

    property string url: ""
    property string title: ""

    readonly property string host: {
        const m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i.exec(root.url);
        return m ? m[1].replace(/^www\./, "") : "";
    }
    readonly property string letter: (root.host || root.title || "?").charAt(0).toUpperCase()

    // stable 32-bit string hash -> hue
    function hue(s) {
        let h = 0;
        for (let i = 0; i < s.length; ++i)
            h = (h * 31 + s.charCodeAt(i)) | 0;
        return (Math.abs(h) % 360) / 360;
    }

    radius: Math.round(width / 4)
    color: Qt.hsla(hue(root.host || root.title), 0.5, Theme.isDark ? 0.42 : 0.55, 1)

    Text {
        anchors.centerIn: parent
        text: root.letter
        color: "white"
        font.family: Theme.fontFamily
        font.pixelSize: Math.round(root.height * 0.62)
        font.weight: Font.DemiBold
    }
}
