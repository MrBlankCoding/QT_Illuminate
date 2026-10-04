import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

Popup {
    id: root

    property var webView: null
    property int matchCount: 0
    property int activeMatch: 0
    property bool hasSearched: false

    popupType: Popup.Window
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    x: parent ? parent.width - width - 16 : 0
    y: 8
    implicitWidth: 300
    implicitHeight: 40
    width: implicitWidth
    height: implicitHeight
    padding: 0

    Timer {
        id: debounceTimer
        interval: 160
        repeat: false
        onTriggered: root.search(false)
    }

    function timedSearch() {
        debounceTimer.restart();
    }

    function dismiss() {
        root.resetSearch();
        root.close();
    }

    function resetSearch() {
        root.hasSearched = false;
        root.matchCount = 0;
        root.activeMatch = 0;
        if (root.webView)
            root.webView.findText("");
    }

    function search(backward) {
        if (!root.webView || input.text.length === 0) {
            root.matchCount = 0;
            root.activeMatch = 0;
            root.hasSearched = false;
            if (root.webView)
                root.webView.findText("");
            return;
        }
        root.hasSearched = true;
        const flags = backward ? CefBrowser.FindBackward : 0;
        root.webView.findText(input.text, flags);
    }

    onOpened: {
        if (input.text.length > 0)
            root.search(false);
        Qt.callLater(() => {
            if (!root.visible)
                return;
            const popupWindow = input.Window.window;
            if (popupWindow) {
                popupWindow.raise();
                popupWindow.requestActivate();
                Qt.callLater(() => {
                    if (root.visible && popupWindow.active)
                        root.focusInput();
                });
            }
        });
    }
    onClosed: {
        root.resetSearch();
        if (root.webView)
            root.webView.forceActiveFocus();
    }

    onWebViewChanged: {
        if (root.visible && input.text.length > 0)
            root.search(false);
    }

    function focusInput() {
        if (!root.visible)
            return;
        input.forceActiveFocus();
        input.selectAll();
    }

    Connections {
        target: input.Window.window
        enabled: input.Window.window !== null
        function onActiveChanged() {
            if (input.Window.window && input.Window.window.active) {
                input.Window.window.raise();
                root.focusInput();
            }
        }
    }

    Connections {
        target: root.webView
        enabled: root.webView !== null
        function onFindTextFinished(numberOfMatches, activeMatchOrdinal, finalUpdate) {
            root.matchCount = numberOfMatches;
            root.activeMatch = numberOfMatches > 0 ? activeMatchOrdinal : 0;
        }
    }

    background: Rectangle {
        radius: 8
        color: Theme.surface
        border.color: Theme.border
        border.width: 1
    }

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 6
        spacing: 4

        TextInput {
            id: input
            objectName: "input"
            Layout.fillWidth: true
            focus: root.visible
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
            Keys.onEscapePressed: root.dismiss()

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

        Text {
            text: "‹"
            font.pixelSize: 20
            font.family: Theme.fontFamily
            color: prevHover.hovered ? Theme.text : Theme.textMuted
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter

            HoverHandler { id: prevHover }
            TapHandler { onTapped: root.search(true) }
        }

        Text {
            text: "›"
            font.pixelSize: 20
            font.family: Theme.fontFamily
            color: nextHover.hovered ? Theme.text : Theme.textMuted
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter

            HoverHandler { id: nextHover }
            TapHandler { onTapped: root.search(false) }
        }

        LucideIcon {
            size: 13
            source: "qrc:/QT_Illuminate/ui/icons/x.svg"
            color: closeHover.hovered ? Theme.text : Theme.textMuted
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 2

            HoverHandler { id: closeHover }
            TapHandler { onTapped: root.dismiss() }
        }
    }
}
