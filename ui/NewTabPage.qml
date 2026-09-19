import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QT_Illuminate.ui


// rendered instead of a WebEngineView
// "newtab://newtab".

Item {
    id: root

    // ── greeting
    function greeting() {
        const h = new Date().getHours()
        if (h < 12) return "Good morning"
        if (h < 18) return "Good afternoon"
        return "Good evening"
    }
    function formattedDate() {
        return new Date().toLocaleDateString(Qt.locale(), "dddd, MMMM d")
    }

    // refresh every minute
    Timer {
        interval: 60000
        running:  true
        repeat:   true
        onTriggered: {
            greetingText.text = root.greeting()
            dateText.text     = root.formattedDate()
        }
    }

    // background
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        TapHandler {
            onTapped: root.forceActiveFocus()
        }
    }

    // domain favicon fetch
    // this should live somewehre else
    function faviconFallback(url) {
        const host = String(url).replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "").split("/")[0]
        return "https://www.google.com/s2/favicons?sz=64&domain=" + host
    }

    // content
    // i miss swift
    Column {
        id: contentCol
        anchors.centerIn: parent
        width:   Math.min(parent.width * 0.72, 680)
        spacing: 36

        // greeting
        Column {
            width:   parent.width
            spacing: 6

            Text {
                id: greetingText
                anchors.horizontalCenter: parent.horizontalCenter
                text:           root.greeting()
                color:          Theme.text
                font.family:    Theme.fontFamily
                font.pixelSize: 36
                font.weight:    Font.Light
            }

            Text {
                id: dateText
                anchors.horizontalCenter: parent.horizontalCenter
                text:           root.formattedDate()
                color:          Theme.textMuted
                font.family:    Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
            }
        }

        // search bar
        Item {
            id: searchArea
            width:  parent.width
            height: 48
            z: 50

            // local bookmarks and remote
            // when history is added, include history items too
            ListModel { id: suggestionModel }
            property int highlighted: -1

            function clearSuggestions() {
                applySuggestions([])
            }

            function applySuggestions(list) {
                suggestionModel.clear()
                for (let i = 0; i < list.length; i++)
                    suggestionModel.append(list[i])
                highlighted = -1
            }

            function acceptSuggestion(i) {
                if (i < 0 || i >= suggestionModel.count) return
                const item = suggestionModel.get(i)
                searchArea.clearSuggestions()
                browser.navigate(item.isBookmark ? item.url : item.text)
            }

            Timer {
                id: suggestTimer
                interval: 150
                repeat:   false
                onTriggered: searchArea.fetchSuggestions(searchInput.text.trim())
            }

            function fetchSuggestions(query) {
                if (query === "") {
                    clearSuggestions()
                    return
                }

                const q = query.toLowerCase()
                const local = []
                for (let i = 0; i < bookmarks.count && local.length < 4; i++) {
                    const bm = bookmarks.get(i)
                    if (bm.title.toLowerCase().includes(q) || bm.url.toLowerCase().includes(q))
                        local.push({ text: bm.title, url: bm.url, isBookmark: true })
                }
                
                // show local matches
                // bookmarks 
                if (local.length > 0)
                    applySuggestions(local)

                const xhr = new XMLHttpRequest()
                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE) return
                    if (xhr.status !== 200) return
                    // drop when query is changed
                    if (searchInput.text.trim() !== query) return
                    try {
                        const data = JSON.parse(xhr.responseText)
                        const remote = data[1] || []
                        const merged = local.slice()
                        for (let i = 0; i < remote.length && merged.length < 8; i++)
                            merged.push({ text: remote[i], url: "", isBookmark: false })
                        applySuggestions(merged)
                    } catch (e) {
                        if (local.length === 0)
                            clearSuggestions()
                    }
                }
                xhr.open("GET", "https://suggestqueries.google.com/complete/search?client=firefox&q=" + encodeURIComponent(query))
                xhr.send()
            }

            Rectangle {
                id: searchPill
                anchors.fill: parent
                radius: Theme.pillRadius
                color:  searchInput.activeFocus ? Theme.surface : Theme.surfaceHigh

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                // focus 
                Rectangle {
                    anchors.fill:  parent
                    radius:        parent.radius
                    color:         "transparent"
                    border.color:  Theme.accent
                    border.width:  searchInput.activeFocus ? 1.5 : 0
                    Behavior on border.width { NumberAnimation { duration: Theme.durationFast } }
                }

                RowLayout {
                    anchors.fill:         parent
                    anchors.leftMargin:   18
                    anchors.rightMargin:  18
                    spacing: 10

                    LucideIcon {
                        size:   16
                        source: "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                        color:  searchInput.activeFocus ? Theme.accent : Theme.textMuted
                        Layout.alignment: Qt.AlignVCenter
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color:            Theme.text
                        font.family:      Theme.fontFamily
                        font.pixelSize:   Theme.fontSizeM
                        selectByMouse:    true
                        clip:             true
                        verticalAlignment: TextInput.AlignVCenter

                        Text {
                            anchors.fill:      parent
                            verticalAlignment: Text.AlignVCenter
                            text:    "Search or enter address"
                            color:   Theme.textMuted
                            font:    searchInput.font
                            visible: searchInput.text === "" && !searchInput.activeFocus
                        }

                        onTextChanged: {
                            searchArea.highlighted = -1
                            suggestTimer.restart()
                        }

                        Keys.onDownPressed: {
                            if (suggestionModel.count > 0)
                                searchArea.highlighted = Math.min(searchArea.highlighted + 1, suggestionModel.count - 1)
                        }
                        Keys.onUpPressed: {
                            if (suggestionModel.count > 0)
                                searchArea.highlighted = Math.max(searchArea.highlighted - 1, -1)
                        }
                        Keys.onReturnPressed: {
                            if (searchArea.highlighted >= 0) {
                                searchArea.acceptSuggestion(searchArea.highlighted)
                            } else if (text.trim() !== "") {
                                searchArea.clearSuggestions()
                                browser.navigate(text.trim())
                            }
                        }
                        Keys.onEscapePressed: {
                            if (suggestionModel.count > 0) {
                                searchArea.clearSuggestions()
                            } else {
                                text  = ""
                                focus = false
                            }
                        }
                    }
                }
            }

            // suggestions
            Rectangle {
                id: suggestionsBox
                anchors.top:  searchPill.bottom
                anchors.left: searchPill.left
                anchors.right: searchPill.right
                anchors.topMargin: 6
                radius: Theme.pillRadius
                color:  Theme.surface
                border.color: Theme.border
                border.width: 1
                visible: suggestionModel.count > 0 && searchInput.activeFocus
                height: suggestionsColumn.implicitHeight + 8
                Behavior on height { NumberAnimation { duration: Theme.durationFast } }

                Column {
                    id: suggestionsColumn
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: suggestionModel

                        delegate: Rectangle {
                            width:  suggestionsColumn.width
                            height: 34
                            radius: 6
                            color:  index === searchArea.highlighted ? Theme.surfaceHigh : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin:  14
                                anchors.rightMargin: 14
                                spacing: 8

                                LucideIcon {
                                    size:   14
                                    source: model.isBookmark
                                            ? "qrc:/QT_Illuminate/ui/ui/icons/star-filled.svg"
                                            : "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                                    color:  Theme.textMuted
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text:           model.text
                                    color:          Theme.text
                                    elide:          Text.ElideRight
                                    font.family:    Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeS
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            HoverHandler {
                                onHoveredChanged: if (hovered) searchArea.highlighted = index
                            }
                            TapHandler {
                                onTapped: searchArea.acceptSuggestion(index)
                            }
                        }
                    }
                }
            }

            // auto focus
            onVisibleChanged: {
                if (visible)
                    searchInput.forceActiveFocus()
            }
        }

        // bookmarks
        Row {
            id: quickLinksRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16
            visible: bookmarksRepeater.count > 0

            Repeater {
                id: bookmarksRepeater
                model: bookmarks

                // single file line
                Item {
                    id: tile
                    width:  92
                    height: 88

                    property bool hovered:  tileHover.hovered
                    property bool renaming: false

                    function startRename() { renaming = true }
                    function commitRename(newTitle) {
                        renaming = false
                        const t = newTitle.trim()
                        if (t !== "" && t !== model.title)
                            bookmarks.renameBookmark(index, t)
                    }

                    Rectangle {
                        anchors.fill:  parent
                        radius:        Theme.tabRadius + 4
                        color:         tile.hovered ? Theme.surfaceHigh : Theme.surface
                        border.color:  tile.hovered ? Theme.border : "transparent"
                        border.width:  1

                        Behavior on color        { ColorAnimation { duration: Theme.durationFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 10

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width:  36
                                height: 36
                                radius: 10
                                color:  Theme.surfaceHigh

                                // prefer favicon when page was warm
                                // fall back to fetch 
                                Image {
                                    id: faviconImg
                                    anchors.centerIn: parent
                                    width:    18
                                    height:   18
                                    fillMode: Image.PreserveAspectFit
                                    smooth:   true
                                    asynchronous: true
                                    visible:  status === Image.Ready
                                    source:   model.iconUrl !== "" ? model.iconUrl : root.faviconFallback(model.url)

                                    onStatusChanged: {
                                        if (status === Image.Error && source !== root.faviconFallback(model.url))
                                            source = root.faviconFallback(model.url)
                                    }
                                }

                                LucideIcon {
                                    anchors.centerIn: parent
                                    size:   18
                                    source: "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                                    color:  tile.hovered ? Theme.accent : Theme.textMuted
                                    visible: faviconImg.status !== Image.Ready
                                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                                }
                            }

                            Text {
                                id: titleText
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 84
                                visible: !tile.renaming
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text:           model.title
                                color:          tile.hovered ? Theme.text : Theme.textMuted
                                font.family:    Theme.fontFamily
                                font.pixelSize: Theme.fontSizeS
                                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                            }

                            TextInput {
                                id: titleEdit
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 84
                                visible: tile.renaming
                                horizontalAlignment: TextInput.AlignHCenter
                                color: Theme.text
                                font.family:    Theme.fontFamily
                                font.pixelSize: Theme.fontSizeS
                                selectByMouse:  true
                                clip: true

                                onVisibleChanged: {
                                    if (visible) {
                                        text = model.title
                                        forceActiveFocus()
                                        selectAll()
                                    }
                                }

                                Keys.onReturnPressed: tile.commitRename(text)
                                Keys.onEscapePressed: tile.renaming = false
                                onActiveFocusChanged: {
                                    if (!activeFocus && tile.renaming)
                                        tile.commitRename(text)
                                }
                            }
                        }
                    }

                    // rename/delete
                    Menu {
                        id: tileMenu
                        popupType: Popup.Native

                        MenuItem {
                            text: "Rename"
                            onTriggered: tile.startRename()
                        }
                        MenuItem {
                            text: "Delete"
                            onTriggered: bookmarks.removeBookmark(index)
                        }
                    }

                    HoverHandler { id: tileHover }
                    TapHandler   { enabled: !tile.renaming; onTapped: browser.navigate(model.url) }
                    TapHandler {
                        enabled: !tile.renaming
                        acceptedButtons: Qt.RightButton
                        onTapped: tileMenu.popup()
                    }
                }
            }
        }
    }

    Component.onCompleted: logger.info("NewTabPage", "New tab page loaded")
}
