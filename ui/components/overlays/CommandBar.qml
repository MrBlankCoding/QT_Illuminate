import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Popup {
    id: root

    property string mode: "new"
    property var quickActions: []

    readonly property int shadowPad: 28
    readonly property int inputRowHeight: 56
    readonly property int rowHeight: 40
    readonly property int maxRows: 8
    readonly property int compactHeight: inputRowHeight + shadowPad * 2
    readonly property int preferredWidth: 736
    readonly property int preferredHeight: 456
    property var results: []
    property int highlighted: 0

    popupType: Popup.Window
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
    padding: shadowPad
    width: Math.min(root.preferredWidth, parent.width - 32)
    height: Math.min(root.preferredHeight, parent.height - y - 16, root.inputRowHeight
        + (root.results.length > 0
            ? Theme.space2 * 2 + 1 + Math.min(root.maxRows, root.results.length) * root.rowHeight
            : 0)
        + root.shadowPad * 2)
    x: Math.round((parent.width - width) / 2)
    y: Math.max(16, Math.round((parent.height - root.compactHeight) / 2))

    function openNew() {
        root.mode = "new";
        input.text = "";
        root.open();
    }

    function openEdit(url) {
        root.mode = "edit";
        input.text = url;
        root.open();
    }

    onOpened: {
        root.rebuild();
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
    onClosed: suggestions.clear()

    function focusInput() {
        if (!root.visible)
            return;
        input.forceActiveFocus();
        input.selectAll();
    }

    Connections {
        target: input.Window.window
        function onActiveChanged() {
            if (input.Window.window && input.Window.window.active) {
                input.Window.window.raise();
                root.focusInput();
            }
        }
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.close()
    }

    function looksLikeUrl(text) {
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text))
            return true;
        return !/\s/.test(text) && (/^[^.\s]+\.[^\s]+$/.test(text) || /^localhost(:\d+)?(\/|$)/i.test(text));
    }

    function rebuild() {
        const text = input.text.trim();
        const q = text.toLowerCase();
        const list = [];

        if (text !== "") {
            const isUrl = root.looksLikeUrl(text);
            list.push({
                kind: "go",
                title: text,
                subtitle: isUrl ? "Open" : "Search " + Prefs.searchEngineName,
                input: text
            });
        }

        // Only show tab matches for a non-empty query, keeping a new command bar compact.
        const tabs = Browser.tabModel;
        let tabMatches = 0;
        for (let i = tabs.count - 1; i >= 0 && tabMatches < 4; --i) {
            if (i === tabs.activeIndex && root.mode === "edit")
                continue;
            const t = tabs.itemAt(i);
            const url = t.url.toString();
            if (url === "newtab://newtab")
                continue;
            if (q === "" || (!t.title.toLowerCase().includes(q) && !url.toLowerCase().includes(q)))
                continue;
            list.push({ kind: "tab", title: t.title, subtitle: "Switch to Tab", tabIndex: i, iconUrl: t.iconUrl, url: url });
            ++tabMatches;
        }

        for (let i = 0; i < suggestions.count; ++i) {
            const s = suggestions.model.get(i);
            if (s.isBookmark)
                list.push({ kind: "bookmark", title: s.text, subtitle: s.url, input: s.url, url: s.url });
            else if (s.text.toLowerCase() !== q)
                list.push({ kind: "suggest", title: s.text, subtitle: "", input: s.text });
        }

        for (let i = 0; i < root.quickActions.length; ++i) {
            const a = root.quickActions[i];
            if (q !== "" && a.label.toLowerCase().includes(q))
                list.push({ kind: "action", title: a.label, subtitle: "Action", icon: a.icon, run: a.run });
        }

        root.results = list;
        root.highlighted = list.length > 0 ? 0 : -1;
    }

    function commit(index, background) {
        const item = index >= 0 ? root.results[index] : null;
        const text = input.text.trim();
        const mode = root.mode;
        root.close();

        if (!item) {
            if (text !== "")
                mode === "edit" || (!background && Browser.activeUrl === "newtab://newtab")
                    ? Browser.navigate(text) : Browser.newTab(text, background);
            return;
        }

        switch (item.kind) {
        case "tab":
            Browser.activateTab(item.tabIndex);
            return;
        case "action":
            item.run();
            return;
        default:
            if (mode === "edit" || (!background && Browser.activeUrl === "newtab://newtab"))
                Browser.navigate(item.input);
            else
                Browser.newTab(item.input, background);
        }
    }

    SuggestionProvider {
        id: suggestions
    }

    Connections {
        target: suggestions.model
        function onCountChanged() { Qt.callLater(root.rebuild) }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast; easing.type: Easing.InQuad }
        NumberAnimation { property: "scale"; to: 0.98; duration: Theme.durationFast; easing.type: Easing.InQuad }
    }

    // the modal dim can't reach over the page's native view; nothing to draw
    Overlay.modal: Item {}

    background: Item {
        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            blur: 28
            offset.y: 8
            color: Theme.shadow
        }
        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: root.shadowPad
            radius: Theme.radiusCommand
            color: Theme.cardBg
            border.width: 1
            border.color: Theme.cardBorder
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: root.inputRowHeight
            Layout.leftMargin: Theme.space4 + 2
            Layout.rightMargin: Theme.space4
            spacing: Theme.space3

            LucideIcon {
                size: 18
                source: "qrc:/QT_Illuminate/ui/ui/icons/search.svg"
                color: Theme.textMuted
            }

            TextInput {
                id: input
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                focus: root.visible
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true
                color: Theme.text
                selectionColor: Theme.accentDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXL

                onTextEdited: {
                    suggestions.update(text);
                    root.rebuild();
                }

                Keys.onDownPressed: root.highlighted = Math.min(root.highlighted + 1, root.results.length - 1)
                Keys.onUpPressed: root.highlighted = Math.max(root.highlighted - 1, 0)
                Keys.onReturnPressed: event => root.commit(root.highlighted, (event.modifiers & Qt.ControlModifier) !== 0)
                Keys.onEnterPressed: event => root.commit(root.highlighted, (event.modifiers & Qt.ControlModifier) !== 0)

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: input.text === ""
                    text: "Search with " + Prefs.searchEngineName + " or enter address"
                    color: Theme.textMuted
                    font: input.font
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: resultList.count > 0
            color: Theme.cardBorder
        }

        ListView {
            id: resultList
            Layout.fillWidth: true
            Layout.preferredHeight: root.results.length > 0
                ? Math.min(root.maxRows, root.results.length) * root.rowHeight + topMargin + bottomMargin
                : 0
            topMargin: Theme.space2
            bottomMargin: Theme.space2
            clip: true
            interactive: contentHeight > height
            model: root.results
            currentIndex: root.highlighted
            highlightFollowsCurrentItem: true
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Item {
                id: row
                required property int index
                required property var modelData
                readonly property bool selected: index === root.highlighted

                width: resultList.width
                height: root.rowHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space2
                    anchors.rightMargin: Theme.space2
                    radius: Theme.radiusItem
                    color: row.selected ? Theme.accentDim : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space4 + 2
                    anchors.rightMargin: Theme.space4 + 2
                    spacing: Theme.space3

                    Item {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16

                        Image {
                            id: favicon
                            anchors.fill: parent
                            sourceSize.width: 32
                            sourceSize.height: 32
                            source: row.modelData.kind === "tab" ? row.modelData.iconUrl : ""
                            visible: status === Image.Ready
                            asynchronous: true
                        }
                        LetterAvatar {
                            anchors.fill: parent
                            visible: !favicon.visible && (row.modelData.kind === "tab" || row.modelData.kind === "bookmark")
                            url: row.modelData.url || ""
                            title: row.modelData.title
                        }
                        LucideIcon {
                            anchors.centerIn: parent
                            size: 15
                            visible: row.modelData.kind === "go" || row.modelData.kind === "suggest" || row.modelData.kind === "action"
                            source: row.modelData.kind === "action" ? row.modelData.icon
                                  : row.modelData.kind === "go" && root.looksLikeUrl(row.modelData.title) ? "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                                  : "qrc:/QT_Illuminate/ui/ui/icons/search.svg"
                            color: Theme.textMuted
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeM
                    }

                    Text {
                        Layout.maximumWidth: resultList.width * 0.4
                        visible: text !== ""
                        text: row.modelData.subtitle
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                    }

                    LucideIcon {
                        visible: row.selected
                        size: 13
                        source: "qrc:/QT_Illuminate/ui/ui/icons/arrow-right.svg"
                        color: Theme.textMuted
                    }
                }

                HoverHandler {
                    onHoveredChanged: if (hovered) root.highlighted = row.index
                }
                TapHandler {
                    onTapped: root.commit(row.index, false)
                }
            }
        }
    }
}
