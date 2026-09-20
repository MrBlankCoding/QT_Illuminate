import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtWebEngine
import QT_Illuminate.ui

// adress bar pill and loading bar
Item {
    id: root
    height: Theme.toolbarHeight + Theme.progressH

    property string currentUrl:  ""
    property string currentTitle: ""
    property string currentIconUrl: ""
    property bool   isLoading:   false
    property int    loadProgress: 0
    property bool   canGoBack:    false
    property bool   canGoForward: false

    // recheck bookmarks on change
    readonly property bool isBookmarked: bookmarks.count >= 0 && root.currentUrl !== "" && bookmarks.isBookmarked(root.currentUrl)

    // ⋮ menu can drive find-in-page and zoom.
    property var findBar: null
    property var zoomIndicator: null
    property var downloadsPanel: null

    // Emitted on submit
    signal navigate(string input)

    // called by shortcut
    function focusAddressBar() {
        addressInput.forceActiveFocus()
        addressInput.selectAll()
    }

    // called on star and shortcut
    function toggleBookmark() {
        if (root.currentUrl === "" || root.currentUrl === "newtab://newtab") return
        bookmarks.toggleBookmark(root.currentTitle, root.currentUrl, root.currentIconUrl)
    }

    // --- search suggestions model & helpers (owned by root so suggestionsBox can use it) ---
    ListModel { id: suggestionModel }
    property int highlighted: -1

    function clearSuggestions() {
        suggestionModel.clear()
        highlighted = -1
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
        clearSuggestions()
        addressInput.focus = false
        root.navigate(item.isBookmark ? item.url : item.text)
    }

    Timer {
        id: suggestTimer
        interval: 150
        repeat:   false
        onTriggered: root.fetchSuggestions(addressInput.text.trim())
    }

    function fetchSuggestions(query) {
        if (query === "" || query === "newtab://newtab") {
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

        if (local.length > 0)
            applySuggestions(local)

        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) return
            if (addressInput.text.trim() !== query) return
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

    // background
    Rectangle {
        id: toolbarBg
        anchors.top: parent.top
        width: parent.width
        height: Theme.toolbarHeight
        color: Theme.toolbarBg
        z: 100

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin:  12
            anchors.rightMargin: 12
            spacing: 8

            // back
            LucideIcon {
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/chevron-left.svg"
                color: backHover.hovered ? Theme.text : Theme.textMuted
                opacity: root.canGoBack ? 1 : 0.35
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: backHover; enabled: root.canGoBack }
                TapHandler { enabled: root.canGoBack; onTapped: browser.goBack() }
            }

            // forward
            LucideIcon {
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/chevron-right.svg"
                color: forwardHover.hovered ? Theme.text : Theme.textMuted
                opacity: root.canGoForward ? 1 : 0.35
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: forwardHover; enabled: root.canGoForward }
                TapHandler { enabled: root.canGoForward; onTapped: browser.goForward() }
            }

            // refresh
            LucideIcon {
                size: 15
                source: root.isLoading
                       ? "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                       : "qrc:/QT_Illuminate/ui/ui/icons/rotate-cw.svg"
                color: reloadHover.hovered ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: reloadHover }
                TapHandler { onTapped: browser.reload() }
            }

            // adress bar itself
            Rectangle {
                id: pill
                Layout.fillWidth: true
                height: 34
                radius: Theme.pillRadius
                color: addressInput.activeFocus ? Theme.bg : Theme.surfaceHigh

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                // Focus
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.color: Theme.accent
                    border.width: addressInput.activeFocus ? 1.5 : 0
                    Behavior on border.width { NumberAnimation { duration: Theme.durationFast } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  14
                    anchors.rightMargin: 10
                    spacing: 6

                    // icons
                    // could make clicable for context menu
                    LucideIcon {
                        id: lockIcon
                        size: 14
                        Layout.alignment: Qt.AlignVCenter
                        opacity: 0.7

                        source: {
                            const u = root.currentUrl
                            if (u.startsWith("https://")) return "qrc:/QT_Illuminate/ui/ui/icons/lock.svg"
                            if (u.startsWith("http://"))  return "qrc:/QT_Illuminate/ui/ui/icons/alert-triangle.svg"
                            return "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                        }
                        color: {
                            const u = root.currentUrl
                            if (u.startsWith("https://")) return Theme.accent
                            if (u.startsWith("http://"))  return Theme.danger
                            return Theme.textMuted
                        }
                    }

                    // url
                    TextInput {
                        id: addressInput
                        Layout.fillWidth: true
                        text:  root.currentUrl
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeM
                        font.family:    Theme.fontFamily
                        selectByMouse:  true
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: {
                            if (activeFocus) {
                                root.highlighted = -1
                                suggestTimer.restart()
                            }
                        }

                        onActiveFocusChanged: {
                            if (activeFocus) {
                                Qt.callLater(selectAll)
                                if (text.trim() !== "" && text !== "newtab://newtab")
                                    suggestTimer.restart()
                            } else {
                                root.clearSuggestions()
                            }
                        }

                        Keys.onDownPressed: {
                            if (suggestionModel.count > 0)
                                root.highlighted = Math.min(root.highlighted + 1, suggestionModel.count - 1)
                        }
                        Keys.onUpPressed: {
                            if (suggestionModel.count > 0)
                                root.highlighted = Math.max(root.highlighted - 1, -1)
                        }
                        Keys.onReturnPressed: {
                            if (root.highlighted >= 0) {
                                root.acceptSuggestion(root.highlighted)
                            } else if (text.trim() !== "") {
                                root.clearSuggestions()
                                focus = false
                                root.navigate(text.trim())
                            }
                        }
                        Keys.onEscapePressed: {
                            if (suggestionModel.count > 0) {
                                root.clearSuggestions()
                            } else {
                                text = root.currentUrl
                                focus = false
                            }
                        }

                        // empty 
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Search or enter address"
                            color: Theme.textMuted
                            font: addressInput.font
                            visible: addressInput.text === "" && !addressInput.activeFocus
                        }
                    }

                    // bookmark toggle
                    LucideIcon {
                        size: 14
                        visible: root.currentUrl !== "" && root.currentUrl !== "newtab://newtab"
                        source: root.isBookmarked
                               ? "qrc:/QT_Illuminate/ui/ui/icons/star-filled.svg"
                               : "qrc:/QT_Illuminate/ui/ui/icons/star.svg"
                        color: root.isBookmarked ? Theme.accent : (starHover.hovered ? Theme.text : Theme.textMuted)
                        Layout.alignment: Qt.AlignVCenter

                        HoverHandler { id: starHover }
                        TapHandler { onTapped: root.toggleBookmark() }
                    }
                }
            }

            // extensions list icons — only pinned & enabled show here
            Repeater {
                model: extensionService

                delegate: Item {
                    width: model.enabled && model.pinned ? 28 : 0
                    height: 28
                    Layout.alignment: Qt.AlignVCenter
                    visible: model.enabled && model.pinned
                    clip: true

                    Behavior on width { NumberAnimation { duration: Theme.durationFast } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: extHover.hovered ? Theme.surfaceHigh : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    }

                    Image {
                        id: extImg
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: {
                            const iconPath = extensionService.getInstalledIconPath(model.id)
                            return iconPath !== "" ? "file://" + iconPath : ""
                        }
                        visible: status === Image.Ready
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    LucideIcon {
                        anchors.centerIn: parent
                        size: 14
                        source: "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                        color: extHover.hovered ? Theme.accent : Theme.textMuted
                        visible: !extImg.visible
                    }

                    HoverHandler { id: extHover }

                    // left click — open popup or navigate
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: {
                            const popupUrl = extensionService.getPopupUrl(model.id)
                            if (popupUrl !== "") {
                                if (extensionPopupView.url.toString() === popupUrl) {
                                    extensionPopupView.reload()
                                } else {
                                    extensionPopupView.url = popupUrl
                                }
                                extensionPopup.open()
                            } else {
                                browser.navigate("illuminate://installed-extensions")
                            }
                        }
                    }

                    // right click — pin/unpin context menu
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: extCtxMenu.popup()
                    }

                    Menu {
                        id: extCtxMenu
                        popupType: Popup.Native

                        MenuItem {
                            text: model.pinned ? "Unpin Extension" : "Pin Extension"
                            onTriggered: extensionService.togglePin(model.id)
                        }
                        MenuSeparator {}
                        MenuItem {
                            text: model.enabled ? "Disable" : "Enable"
                            onTriggered: extensionService.toggleExtension(model.id)
                        }
                        MenuItem {
                            text: "Manage Extensions"
                            onTriggered: browser.navigate("illuminate://installed-extensions")
                        }
                    }
                }
            }

            // downloads
            LucideIcon {
                id: downloadsButton
                visible: root.downloadsPanel && root.downloadsPanel.downloadCount > 0
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/download.svg"
                color: (downloadsHover.hovered || (root.downloadsPanel && root.downloadsPanel.visible)) ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: downloadsHover }
                TapHandler { onTapped: root.downloadsPanel && root.downloadsPanel.toggle() }

                // active
                Rectangle {
                    visible: root.downloadsPanel && root.downloadsPanel.activeCount > 0
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -1
                    anchors.rightMargin: -1
                }
            }

            // app menu
            LucideIcon {
                id: menuButton
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/more-vertical.svg"
                color: (menuHover.hovered || appMenu.visible) ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: menuHover }
                TapHandler { onTapped: appMenu.popup() }

                Menu {
                    id: appMenu
                    popupType: Popup.Native

                    MenuItem {
                        text: "New Tab"
                        onTriggered: browser.newTab()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Zoom In"
                        onTriggered: root.zoomIndicator && root.zoomIndicator.zoomBy(0.1)
                    }
                    MenuItem {
                        text: "Zoom Out"
                        onTriggered: root.zoomIndicator && root.zoomIndicator.zoomBy(-0.1)
                    }
                    MenuItem {
                        text: "Reset Zoom" + (root.zoomIndicator ? " (" + root.zoomIndicator.zoomPercent + "%)" : "")
                        onTriggered: root.zoomIndicator && root.zoomIndicator.zoomReset()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Find in Page…"
                        onTriggered: root.findBar && root.findBar.open()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: root.isBookmarked ? "Remove Bookmark" : "Bookmark This Page"
                        enabled: root.currentUrl !== "" && root.currentUrl !== "newtab://newtab"
                        onTriggered: root.toggleBookmark()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Downloads"
                        onTriggered: root.downloadsPanel && root.downloadsPanel.toggle()
                    }

                    MenuItem {
                        text: "Extensions"
                        onTriggered: browser.navigate("illuminate://extensions")
                    }
                    MenuItem {
                        text: "Installed Extensions"
                        onTriggered: browser.navigate("illuminate://installed-extensions")
                    }

                    MenuItem {
                        text: "Installed Extensions"
                        onTriggered: browser.navigate("illuminate://installed-extensions")
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Theme: System" + (browser.themeMode === "system" ? " ✓" : "")
                        onTriggered: browser.themeMode = "system"
                    }
                    MenuItem {
                        text: "Theme: Dark" + (browser.themeMode === "dark" ? " ✓" : "")
                        onTriggered: browser.themeMode = "dark"
                    }
                    MenuItem {
                        text: "Theme: Light" + (browser.themeMode === "light" ? " ✓" : "")
                        onTriggered: browser.themeMode = "light"
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Developer Tools"
                        onTriggered: browser.toggleDevTools()
                    }
                }
            }
        }
    }

    // search suggestions dropdown (child of root Item, positioned relative to address pill)
    // Uses mapFromItem to translate pill's bottom position into root coordinates
    Rectangle {
        id: suggestionsBox
        anchors.left: toolbarBg.left
        anchors.right: toolbarBg.right
        anchors.top: toolbarBg.bottom
        anchors.topMargin: -Theme.toolbarHeight
        height: suggestionModel.count > 0 ? (suggestionsColumn.implicitHeight + 8) : 0
        visible: suggestionModel.count > 0 && addressInput.activeFocus
        z: 200
        radius: 8
        color: Theme.surface
        border.color: Theme.border
        border.width: 1
        opacity: visible ? 1 : 0
        Behavior on height { NumberAnimation { duration: Theme.durationFast } }
        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

        Column {
            id: suggestionsColumn
            width: parent.width
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: suggestionModel

                delegate: Rectangle {
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
                            source: model.isBookmark
                                    ? "qrc:/QT_Illuminate/ui/ui/icons/star-filled.svg"
                                    : "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
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
                        onHoveredChanged: if (hovered) root.highlighted = index
                    }
                    TapHandler {
                        onTapped: root.acceptSuggestion(index)
                    }
                }
            }
        }
    }

    // extension action popup
    Popup {
        id: extensionPopup
        width: 360
        height: 520
        x: root.width - width - 20
        y: Theme.toolbarHeight + 4
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        onClosed: extensionPopupView.url = "about:blank"

        background: Rectangle {
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            radius: 10
            clip: true
        }

        contentItem: Item {
            anchors.fill: parent
            WebEngineView {
                id: extensionPopupView
                anchors.fill: parent
                backgroundColor: Theme.surface
            }
        }
    }

    // load stipe
    Item {
        id: progressStripe
        anchors.top:  toolbarBg.bottom
        width: parent.width
        height: Theme.progressH

        Rectangle {
            id: progressFill
            anchors.left: parent.left
            anchors.top:  parent.top
            height: parent.height
            width: parent.width * (root.loadProgress / 100)
            color: Theme.accent
            opacity: (root.isLoading && root.loadProgress > 0 && root.loadProgress < 100) ? 1 : 0

            Behavior on width   { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
            Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
        }
    }

    // sync when tab changes
    // why couldnt i do this in swift with webkit
    // i have no clue
    onCurrentUrlChanged: {
        if (!addressInput.activeFocus)
            addressInput.text = root.currentUrl
    }
}
