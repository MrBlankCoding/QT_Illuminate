import QtQuick
import QT_Illuminate.ui

Item {
    id: root

    readonly property ListModel model: suggestionModel
    readonly property int count: suggestionModel.count
    property string query: ""

    ListModel {
        id: suggestionModel
    }

    property var localMatches: []
    function update(text) {
        root.query = text.trim();
        debounce.restart();
    }

    function clear() {
        debounce.stop();
        remoteRequest.cancel();
        root.query = "";
        root.localMatches = [];
        suggestionModel.clear();
    }

    // what to navigate to for row i: a bookmark's/history URL, or the completion text
    function inputAt(i) {
        if (i < 0 || i >= suggestionModel.count)
            return "";
        const item = suggestionModel.get(i);
        return ((item.isBookmark || item.isHistory) ? item.url : item.text) || item.text;
    }

    function apply(list) {
        suggestionModel.clear();
        for (let i = 0; i < list.length; i++)
            suggestionModel.append(list[i]);
    }

    Timer {
        id: debounce
        interval: 150
        onTriggered: root.fetch(root.query)
    }

    SearchSuggestionRequest {
        id: remoteRequest
        onSuggestionsReady: function (query, values) {
            if (query !== root.query)
                return;
            const merged = root.localMatches.slice();
            for (let i = 0; i < values.length && merged.length < 8; i++) {
                const suggestion = values[i];
                if (!merged.some(item => item.text.toLowerCase() === suggestion.toLowerCase()))
                    merged.push({ text: suggestion, url: "", isBookmark: false });
            }
            root.apply(merged);
        }
    }

    function fetch(query) {
        if (query === "") {
            suggestionModel.clear();
            return;
        }

        const q = query.toLowerCase();
        const local = [];

        // bookmarks first (up to 3)
        for (let i = 0; i < Bookmarks.count && local.length < 3; i++) {
            const bm = Bookmarks.itemAt(i);
            if (bm.title.toLowerCase().includes(q) || bm.url.toLowerCase().includes(q))
                local.push({ text: bm.title, url: bm.url, isBookmark: true, isHistory: false });
        }

        // history next (up to 4 total with bookmarks)
        const histResults = History.search(query, 8);
        for (let j = 0; j < histResults.length && local.length < 4; j++) {
            const h = histResults[j];
            // skip if already covered by a bookmark match
            if (!local.some(item => item.url === h.url))
                local.push({ text: h.title || h.url, url: h.url, isBookmark: false, isHistory: true });
        }

        root.localMatches = local;
        root.apply(local);
        remoteRequest.cancel();
        if (!Prefs.searchSuggestionsEnabled)
            return;
        remoteRequest.fetch(query);
    }
}
