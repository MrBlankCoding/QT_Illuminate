import QtQuick
import QtQuick.Layouts
import QtWebEngine
import QT_Illuminate.ui

Item {
    id: root
    property var webView: null
    property int matchCount: 0
    property int activeMatch: 0
    property bool hasSearched: false

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: 8
    anchors.rightMargin: 16
    width: 300
    height: 40
    visible: false
    z: 100

    Timer {
        id: debounceTimer
        interval: 160
        repeat: false
        onTriggered: root.search(false)
    }

    // debounce findText() against per-keystroke churn
    function timedSearch() {
        debounceTimer.restart();
    }

    function open() {
        visible = true;
        Qt.callLater(function () {
            input.forceActiveFocus();
            input.selectAll();
        });
        if (input.text.length > 0)
            search(false);
    }

    function close() {
        visible = false;
        hasSearched = false;
        matchCount = 0;
        activeMatch = 0;
        if (webView)
            webView.findText("");
        if (webView)
            webView.forceActiveFocus();
    }

    function search(backward) {
        if (!webView || input.text.length === 0) {
            matchCount = 0;
            activeMatch = 0;
            hasSearched = false;
            if (webView)
                webView.findText("");
            return;
        }
        hasSearched = true;
        const flags = backward ? WebEngineView.FindBackward : 0;
        webView.findText(input.text, flags);
    }

    // rerun search on tab switch
    onWebViewChanged: {
        if (visible && input.text.length > 0)
            search(false);
    }

    // findText()'s own callback isn't invoked by QtWebEngine build
    // read match counts off this signal instead.
    Connections {
        target: root.webView
        function onFindTextFinished(result) {
            root.matchCount = result.numberOfMatches;
            root.activeMatch = result.numberOfMatches > 0 ? result.activeMatch : 0;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.surface
        border.color: Theme.border
        border.width: 1

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 6
            }
            spacing: 4

            TextInput {
                id: input
                objectName: "input"
                Layout.fillWidth: true
                color: Theme.text
                font.pixelSize: Theme.fontSizeM
                font.family: Theme.fontFamily
                selectByMouse: true
                clip: true
                verticalAlignment: TextInput.AlignVCenter

                onTextChanged: root.timedSearch()

                Keys.onReturnPressed: function (event) {
                    debounceTimer.stop();
                    root.search((event.modifiers & Qt.ShiftModifier) !== 0);
                }
                Keys.onEscapePressed: root.close()

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Find in page"
                    color: Theme.textMuted
                    font: input.font
                    visible: input.text === "" && !input.activeFocus
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 4
                text: root.hasSearched ? (root.activeMatch + "/" + root.matchCount) : ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeS
                font.family: Theme.fontFamily
            }

            // previous
            Text {
                text: "‹"
                font.pixelSize: 20
                font.family: Theme.fontFamily
                color: prevHover.hovered ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter

                HoverHandler {
                    id: prevHover
                }
                TapHandler {
                    onTapped: root.search(true)
                }
            }

            // next
            Text {
                text: "›"
                font.pixelSize: 20
                font.family: Theme.fontFamily
                color: nextHover.hovered ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter

                HoverHandler {
                    id: nextHover
                }
                TapHandler {
                    onTapped: root.search(false)
                }
            }

            // close
            LucideIcon {
                size: 13
                source: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                color: closeHover.hovered ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 2

                HoverHandler {
                    id: closeHover
                }
                TapHandler {
                    onTapped: root.close()
                }
            }
        }
    }
}
