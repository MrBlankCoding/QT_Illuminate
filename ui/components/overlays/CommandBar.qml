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
    property var internalSchemes: ["newtab", "about", "qrc", "chrome", "devtools", "view-source"]

    readonly property int shadowPad: 28
    readonly property int inputRowHeight: 56
    readonly property int rowHeight: 40
    readonly property int maxRows: 8
    readonly property int preferredWidth: 736
    readonly property int compactHeight: inputRowHeight + shadowPad * 2
    readonly property real listChrome: Theme.space2 * 2 + 1
    readonly property real maxCardHeight: inputRowHeight + listChrome + maxRows * rowHeight
    readonly property real preferredHeight: maxCardHeight + shadowPad * 2
    readonly property real cardTargetHeight: Math.min(
        inputRowHeight + (visibleRows > 0 ? listChrome + visibleRows * rowHeight : 0),
        availableHeight)

    property int highlighted: -1
    property bool navigated: false
    property int visibleRows: 0
    property bool queryActive: false
    property string suggestionsQuery: ""
    property bool settling: false
    property var heldSuggestions: []
    property point lastPointer: Qt.point(-1, -1)

    popupType: Popup.Window
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
    padding: shadowPad
    width: Math.min(root.preferredWidth, parent.width - 32)
    height: Math.min(root.preferredHeight, parent.height - 32)
    x: Math.round((parent.width - width) / 2)
    y: Math.max(16, Math.round((parent.height - height) / 2))

    ChromeGlass {
        popupTarget: root
    }

    function resetState() {
        rebuildTimer.stop();
        suggestTimer.stop();
        settleTimer.stop();
        shrinkTimer.stop();
        root.settling = false;
        root.queryActive = false;
        root.navigated = false;
        root.highlighted = -1;
        root.visibleRows = 0;
        root.suggestionsQuery = "";
        root.heldSuggestions = [];
        resultsModel.clear();
        suggestions.clear();
    }

    function openNew() {
        root.resetState();
        root.mode = "new";
        input.text = "";
        root.open();
    }

    function openEdit(url) {
        root.resetState();
        root.mode = "edit";
        const u = String(url);
        input.text = root.isInternalUrl(u) ? "" : u;
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
                        root.focusInput(true);
                });
            }
        });
    }
    onClosed: root.resetState()

    onHighlightedChanged: {
        if (highlighted >= 0)
            resultList.positionViewAtIndex(highlighted, ListView.Contain);
    }

    function focusInput(selectAll) {
        if (!root.visible)
            return;
        input.forceActiveFocus();
        if (selectAll)
            input.selectAll();
    }

    Connections {
        target: input.Window.window
        enabled: input.Window.window !== null
        function onActiveChanged() {
            if (input.Window.window && input.Window.window.active) {
                input.Window.window.raise();
                root.focusInput(false);
            }
        }
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.close()
    }

    QtObject {
        id: regexCache
        readonly property var schemeRegex: /^[a-z][a-z0-9+.-]*:\/\//i
        readonly property var whitespaceRegex: /\s/
        readonly property var domainRegex: /^[^.\s]+\.[^\s]+$/
        readonly property var localhostRegex: /^localhost(:\d+)?(\/|$)/i
        readonly property var schemePrefixRegex: /^([a-z][a-z0-9+.-]*):/i
        readonly property var stripSchemeRegex: /^[a-z][a-z0-9+.-]*:\/\/(www\.)?/i
        readonly property var wordBoundaryRegex: /[\s\/._\-:]/
    }

    function looksLikeUrl(text) {
        if (regexCache.schemeRegex.test(text))
            return true;
        return !regexCache.whitespaceRegex.test(text) && (regexCache.domainRegex.test(text) || regexCache.localhostRegex.test(text));
    }

    function isInternalUrl(url) {
        if (regexCache.whitespaceRegex.test(url))
            return false;
        const m = regexCache.schemePrefixRegex.exec(url);
        return m !== null && root.internalSchemes.indexOf(m[1].toLowerCase()) !== -1;
    }

    function stripScheme(url) {
        return url.replace(regexCache.stripSchemeRegex, "");
    }

    function matchScore(haystack, q) {
        const h = String(haystack).toLowerCase();
        const i = h.indexOf(q);
        if (i < 0)
            return 0;
        if (i === 0)
            return 3;
        return regexCache.wordBoundaryRegex.test(h.charAt(i - 1)) ? 2 : 1;
    }

    function makeRow(kind, key, fields) {
        return Object.assign({
            key: key,
            kind: kind,
            title: "",
            subtitle: "",
            dest: "",
            url: "",
            iconUrl: "",
            icon: "",
            tabIndex: -1,
            actionIndex: -1
        }, fields);
    }

    function sameRow(a, b) {
        return a.kind === b.kind && a.title === b.title && a.subtitle === b.subtitle
            && a.dest === b.dest && a.url === b.url && a.iconUrl === b.iconUrl
            && a.icon === b.icon && a.tabIndex === b.tabIndex && a.actionIndex === b.actionIndex;
    }

    function requestSuggestions() {
        const text = input.text;
        if (text.trim() === "")
            return;
        root.suggestionsQuery = text.trim().toLowerCase();
        root.settling = true;
        settleTimer.restart();
        suggestions.update(text);
    }

    function compatible(list, q) {
        return list.filter(s => s.text.toLowerCase().includes(q)
                                || (s.url !== "" && s.url.toLowerCase().includes(q)));
    }

    function readSuggestions(q) {
        const sm = suggestions.model;
        const fresh = [];
        for (let i = 0; i < sm.count; ++i) {
            const s = sm.get(i);
            if (!s)
                continue;
            fresh.push({
                text: String(s.text),
                url: s.isBookmark ? String(s.url) : "",
                isBookmark: !!s.isBookmark
            });
        }
        const stale = root.suggestionsQuery !== q;
        if (fresh.length > 0) {
            root.heldSuggestions = fresh;
            return stale ? root.compatible(fresh, q) : fresh;
        }
        if (stale || root.settling)
            return root.compatible(root.heldSuggestions, q);
        return [];
    }

    function buildResults() {
        const text = input.text.trim();
        if (text === "" || !root.queryActive)
            return [];

        const q = text.toLowerCase();

        const go = root.makeRow("go", "go", {
            title: text,
            subtitle: root.looksLikeUrl(text) ? "Open" : "Search " + Prefs.searchEngineName,
            dest: text
        });

        const actionHits = [];
        for (let i = 0; i < root.quickActions.length; ++i) {
            const score = root.matchScore(root.quickActions[i].label, q);
            if (score > 0)
                actionHits.push({ score: score, order: i });
        }
        actionHits.sort((a, b) => b.score - a.score || a.order - b.order);
        const actionRows = actionHits.slice(0, 2).map(h => {
            const a = root.quickActions[h.order];
            return root.makeRow("action", "action:" + a.label, {
                title: String(a.label),
                subtitle: "Action",
                icon: String(a.icon || ""),
                actionIndex: h.order
            });
        });

        const tabs = Browser.tabModel;
        const tabHits = [];
        const tabUrls = {};
        for (let i = tabs.count - 1; i >= 0; --i) {
            if (root.mode === "edit" && i === tabs.activeIndex)
                continue;
            const t = tabs.itemAt(i);
            if (!t)
                continue;
            const url = t.url.toString();
            if (root.isInternalUrl(url))
                continue;
            const title = String(t.title || "");
            const score = Math.max(root.matchScore(title, q), root.matchScore(root.stripScheme(url), q));
            if (score > 0)
                tabHits.push({ score: score, order: tabHits.length, index: i, title: title, url: url, iconUrl: t.iconUrl.toString() });
        }
        tabHits.sort((a, b) => b.score - a.score || a.order - b.order);
        const tabRows = tabHits.slice(0, 3).map(h => {
            tabUrls[h.url] = true;
            return root.makeRow("tab", "tab:" + h.index + ":" + h.url, {
                title: h.title,
                subtitle: "Switch to Tab",
                url: h.url,
                iconUrl: h.iconUrl,
                tabIndex: h.index
            });
        });

        const bookmarkRows = [];
        const searchRows = [];
        const seen = {};
        const fromProvider = root.readSuggestions(q);
        for (let i = 0; i < fromProvider.length; ++i) {
            const s = fromProvider[i];
            if (s.isBookmark) {
                if (root.isInternalUrl(s.url) || tabUrls[s.url])
                    continue;
                bookmarkRows.push(root.makeRow("bookmark", "bookmark:" + s.url, {
                    title: s.text,
                    subtitle: s.url,
                    dest: s.url,
                    url: s.url
                }));
            } else {
                const k = s.text.toLowerCase();
                if (k === q || seen[k] || root.isInternalUrl(s.text))
                    continue;
                seen[k] = true;
                searchRows.push(root.makeRow("suggest", "suggest:" + k, {
                    title: s.text,
                    dest: s.text
                }));
            }
        }

        const local = actionRows.concat(tabRows, bookmarkRows.slice(0, 2)).slice(0, root.maxRows - 3);
        const suggs = searchRows.slice(0, root.maxRows - 1 - local.length);
        return [go].concat(local, suggs);
    }

    function syncModel(next) {
        for (let i = 0; i < next.length; ++i) {
            const row = next[i];
            let at = -1;
            for (let j = i; j < resultsModel.count; ++j) {
                if (resultsModel.get(j).key === row.key) {
                    at = j;
                    break;
                }
            }
            if (at < 0) {
                resultsModel.insert(i, row);
            } else {
                if (at !== i)
                    resultsModel.move(at, i, 1);
                if (!root.sameRow(resultsModel.get(i), row))
                    resultsModel.set(i, row);
            }
        }
        if (resultsModel.count > next.length)
            resultsModel.remove(next.length, resultsModel.count - next.length);
    }

    function rebuild() {
        if (!root.visible)
            return;
        rebuildTimer.stop();

        const keepKey = (root.navigated && root.highlighted >= 0 && root.highlighted < resultsModel.count)
                ? resultsModel.get(root.highlighted).key : "";

        root.syncModel(root.buildResults());

        let idx = -1;
        for (let i = 0; keepKey !== "" && i < resultsModel.count; ++i) {
            if (resultsModel.get(i).key === keepKey) {
                idx = i;
                break;
            }
        }
        if (idx < 0)
            root.navigated = false;
        root.highlighted = idx >= 0 ? idx : (resultsModel.count > 0 ? 0 : -1);
        root.updateVisibleRows();
    }

    function updateVisibleRows() {
        const target = Math.min(root.maxRows, resultsModel.count);
        if (target === 0 || target > root.visibleRows) {
            shrinkTimer.stop();
            root.visibleRows = target;
        } else if (target < root.visibleRows) {
            shrinkTimer.restart();
        } else {
            shrinkTimer.stop();
        }
    }

    function handleEdit() {
        root.queryActive = true;
        root.navigated = false;
        if (input.text.trim() === "") {
            suggestTimer.stop();
            settleTimer.stop();
            root.settling = false;
            root.suggestionsQuery = "";
            root.heldSuggestions = [];
            suggestions.clear();
        } else {
            suggestTimer.restart();
        }
        root.rebuild();
    }

    function moveHighlight(delta) {
        const n = resultsModel.count;
        if (n === 0)
            return;
        root.navigated = true;
        if (root.highlighted < 0)
            root.highlighted = delta > 0 ? 0 : n - 1;
        else
            root.highlighted = (root.highlighted + delta + n) % n;
    }

    function hoverHighlight(i) {
        if (root.highlighted === i)
            return;
        root.navigated = true;
        root.highlighted = i;
    }

    function completeHighlighted() {
        if (root.highlighted < 0 || root.highlighted >= resultsModel.count)
            return;
        const r = resultsModel.get(root.highlighted);
        if (r.kind !== "suggest" && r.kind !== "bookmark")
            return;
        input.text = r.dest;
        input.cursorPosition = input.text.length;
        root.handleEdit();
    }

    function commit(index, background) {
        const row = index >= 0 && index < resultsModel.count ? resultsModel.get(index) : null;
        const typed = input.text.trim();

        const kind = row ? row.kind : "";
        const dest = row ? row.dest : typed;
        const tabIndex = row ? row.tabIndex : -1;
        const action = kind === "action" ? root.quickActions[row.actionIndex] : null;
        const reuseTab = root.mode === "edit"
                || (!background && String(Browser.activeUrl) === "newtab://newtab");

        root.close();

        if (kind === "tab") {
            Browser.activateTab(tabIndex);
            return;
        }
        if (kind === "action") {
            if (action)
                action.run();
            return;
        }
        if (dest === "")
            return;
        if (reuseTab)
            Browser.navigate(dest);
        else
            Browser.newTab(dest, background);
    }

    ListModel {
        id: resultsModel
    }

    SuggestionProvider {
        id: suggestions
    }

    Connections {
        target: suggestions.model
        function onCountChanged() { rebuildTimer.restart() }
        function onDataChanged() { rebuildTimer.restart() }
        function onModelReset() { rebuildTimer.restart() }
        function onRowsInserted() { rebuildTimer.restart() }
        function onRowsRemoved() { rebuildTimer.restart() }
    }

    Timer {
        id: rebuildTimer
        interval: 30
        onTriggered: root.rebuild()
    }

    Timer {
        id: suggestTimer
        interval: 90
        onTriggered: root.requestSuggestions()
    }

    Timer {
        id: settleTimer
        interval: 350
        onTriggered: {
            root.settling = false;
            root.rebuild();
        }
    }

    Timer {
        id: shrinkTimer
        interval: 320
        onTriggered: root.visibleRows = Math.min(root.maxRows, resultsModel.count)
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast; easing.type: Easing.InQuad }
        NumberAnimation { property: "scale"; to: 0.98; duration: Theme.durationFast; easing.type: Easing.InQuad }
    }

    Overlay.modal: Item {}

    background: Item {
        RectangularShadow {
            anchors.top: parent.top
            anchors.topMargin: root.shadowPad
            anchors.horizontalCenter: parent.horizontalCenter
            width: card.width
            height: card.height
            radius: card.radius
            blur: 28
            offset.y: 8
            color: Theme.shadow
        }

        Rectangle {
            id: card
            anchors.top: parent.top
            anchors.topMargin: root.shadowPad
            anchors.left: parent.left
            anchors.leftMargin: root.shadowPad
            anchors.right: parent.right
            anchors.rightMargin: root.shadowPad
            height: root.cardTargetHeight
            Behavior on height {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            radius: Theme.radiusCommand
            color: Theme.glassCardBg
            border.width: 1
            border.color: Theme.cardBorder
            clip: true
        }
    }

    contentItem: Item {
        Item {
            id: viewport
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: card.height
            clip: true

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.cardTargetHeight
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.inputRowHeight
                    Layout.leftMargin: Theme.space4 + 2
                    Layout.rightMargin: Theme.space4
                    spacing: Theme.space3

                    LucideIcon {
                        size: 18
                        source: "qrc:/QT_Illuminate/ui/icons/search.svg"
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

                        onTextEdited: root.handleEdit()

                        Keys.onDownPressed: root.moveHighlight(1)
                        Keys.onUpPressed: root.moveHighlight(-1)
                        Keys.onTabPressed: event => {
                            root.completeHighlighted();
                            event.accepted = true;
                        }
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

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    opacity: root.visibleRows > 0 ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.cardBorder
                        }

                        ListView {
                            id: resultList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            topMargin: Theme.space2
                            bottomMargin: Theme.space2
                            clip: true
                            interactive: contentHeight > height
                            boundsBehavior: Flickable.StopAtBounds
                            model: resultsModel

                            delegate: Item {
                                id: row

                                required property int index
                                required property string kind
                                required property string title
                                required property string subtitle
                                required property string url
                                required property string iconUrl
                                required property string icon
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
                                            source: row.kind === "tab" ? row.iconUrl : ""
                                            visible: status === Image.Ready
                                            asynchronous: true
                                            onStatusChanged: {
                                                if (status === Image.Error)
                                                    source = "";
                                            }
                                        }
                                        LetterAvatar {
                                            anchors.fill: parent
                                            visible: !favicon.visible && (row.kind === "tab" || row.kind === "bookmark")
                                            url: row.url
                                            title: row.title
                                        }
                                        LucideIcon {
                                            anchors.centerIn: parent
                                            size: 15
                                            visible: row.kind === "go" || row.kind === "suggest" || row.kind === "action"
                                            source: row.kind === "action" ? row.icon
                                                  : row.kind === "go" && root.looksLikeUrl(row.title) ? "qrc:/QT_Illuminate/ui/icons/globe.svg"
                                                  : "qrc:/QT_Illuminate/ui/icons/search.svg"
                                            color: Theme.textMuted
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: row.title
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeM
                                    }

                                    Text {
                                        Layout.maximumWidth: resultList.width * 0.4
                                        visible: text !== ""
                                        text: row.subtitle
                                        textFormat: Text.PlainText
                                        elide: Text.ElideMiddle
                                        color: Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeS
                                    }

                                    LucideIcon {
                                        visible: row.selected
                                        size: 13
                                        source: "qrc:/QT_Illuminate/ui/icons/arrow-right.svg"
                                        color: Theme.textMuted
                                    }
                                }

                                HoverHandler {
                                    onPointChanged: {
                                        const p = point.scenePosition;
                                        if (p.x === root.lastPointer.x && p.y === root.lastPointer.y)
                                            return;
                                        root.lastPointer = Qt.point(p.x, p.y);
                                        root.hoverHighlight(row.index);
                                    }
                                }
                                TapHandler {
                                    onTapped: root.commit(row.index, false)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
