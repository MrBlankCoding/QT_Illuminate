import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

    // adress bar pill and loading bar
    Item {
        id: root
        height: Theme.toolbarHeight + Theme.progressH

    property string currentUrl: ""
    property string currentTitle: ""
    property string currentIconUrl: ""
    property bool isLoading: false
    property int loadProgress: 0
    property bool canGoBack: false
    property bool canGoForward: false

    // emitted when user picks a profile or opens selector
    signal switchToProfile(var profile)
    signal openProfileSelector
    signal openSettings

    // avatar color helper (mirrors ProfilePicker.avatarColorFor)
    function avatarColorFor(profile) {
        return profile && profile.color && profile.color.length > 0 ? profile.color : "#4A90E2";
    }

    // recheck bookmarks on change
    readonly property bool isBookmarked: Bookmarks.count >= 0 && root.currentUrl !== "" && Bookmarks.isBookmarked(root.currentUrl)

    // ⋮ menu can drive find-in-page and zoom.
    property var findBar: null
    property var zoomIndicator: null
    property var downloadsPanel: null

    // Emitted on submit
    signal navigate(string input)

    // called by shortcut
    function focusAddressBar() {
        addressInput.forceActiveFocus();
        addressInput.selectAll();
    }

    // called on star and shortcut
    function toggleBookmark() {
        if (root.currentUrl === "" || root.currentUrl === "newtab://newtab")
            return;
        Bookmarks.toggleBookmark(root.currentTitle, root.currentUrl, root.currentIconUrl);
    }

    ListModel {
        id: suggestionModel
    }

    property var suggestionXhr: null

    function clearSuggestions() {
        suggestionModel.clear();
        suggestionsBox.highlighted = -1;
    }

    function applySuggestions(list) {
        suggestionModel.clear();
        for (let i = 0; i < list.length; i++)
            suggestionModel.append(list[i]);
        suggestionsBox.highlighted = -1;
    }

function acceptSuggestion(i) {
        if (i < 0 || i >= suggestionModel.count)
            return;
        const item = suggestionModel.get(i);
        // Capture the target before clearing: get()'s object is tied to the
        // model row and reading it after clearSuggestions() yields empty.
        const input = (item.isBookmark ? item.url : item.text) || item.text;
        clearSuggestions();
        addressInput.focus = false;
        root.navigate(input);
    }

    Timer {
        id: suggestTimer
        interval: 150
        repeat: false
        onTriggered: root.fetchSuggestions(addressInput.text.trim())
    }

    function fetchSuggestions(query) {
        if (query === "" || query === "newtab://newtab") {
            clearSuggestions();
            return;
        }

        const q = query.toLowerCase();
        const local = [];
        for (let i = 0; i < Bookmarks.count && local.length < 4; i++) {
            const bm = Bookmarks.itemAt(i);
            if (bm.title.toLowerCase().includes(q) || bm.url.toLowerCase().includes(q))
                local.push({
                    text: bm.title,
                    url: bm.url,
                    isBookmark: true
                });
        }

        if (local.length > 0)
            applySuggestions(local);

        if (root.suggestionXhr)
            root.suggestionXhr.abort();

        const xhr = new XMLHttpRequest();
        root.suggestionXhr = xhr;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr !== root.suggestionXhr)
                return;
            if (xhr.status !== 200)
                return;
            if (addressInput.text.trim() !== query)
                return;
            try {
                const data = JSON.parse(xhr.responseText);
                const remote = data[1] || [];
                const merged = local.slice();
                for (let i = 0; i < remote.length && merged.length < 8; i++)
                    merged.push({
                        text: remote[i],
                        url: "",
                        isBookmark: false
                    });
                applySuggestions(merged);
            } catch (e) {
                if (local.length === 0)
                    clearSuggestions();
            }
        };
        xhr.open("GET", "https://suggestqueries.google.com/complete/search?client=firefox&q=" + encodeURIComponent(query));
        xhr.send();
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
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            // nav pill
            Rectangle {
                Layout.preferredHeight: 32
                Layout.preferredWidth: navRow.implicitWidth + 16
                radius: Theme.pillRadius
                color: Theme.surfaceHigh

                Row {
                    id: navRow
                    anchors.centerIn: parent
                    spacing: 2

                    // one hoverable round button per nav action
                    component NavButton: Item {
                        id: navButton
                        required property string icon
                        property bool canUse: true
                        property int size: 18
                        width: 28
                        height: 28

                        signal clicked

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: navButton.canUse && hoverHandler.hovered ? Theme.tabHover : "transparent"
                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.durationFast
                                }
                            }
                        }

                        LucideIcon {
                            anchors.centerIn: parent
                            size: navButton.size
                            source: navButton.icon
                            color: navButton.canUse ? Theme.text : Theme.textMuted
                            opacity: navButton.canUse ? 1 : 0.4
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.durationFast
                                }
                            }
                        }

                        HoverHandler {
                            id: hoverHandler
                            enabled: navButton.canUse
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            enabled: navButton.canUse
                            onTapped: navButton.clicked()
                        }
                    }

                    NavButton {
                        icon: "qrc:/QT_Illuminate/ui/ui/icons/chevron-left.svg"
                        canUse: root.canGoBack
                        onClicked: Browser.goBack()
                    }
                    NavButton {
                        icon: "qrc:/QT_Illuminate/ui/ui/icons/chevron-right.svg"
                        canUse: root.canGoForward
                        onClicked: Browser.goForward()
                    }
                    NavButton {
                        icon: root.isLoading ? "qrc:/QT_Illuminate/ui/ui/icons/x.svg" : "qrc:/QT_Illuminate/ui/ui/icons/rotate-cw.svg"
                        size: 15
                        canUse: root.currentUrl !== ""
                        onClicked: Browser.reload()
                    }
                }
            }

            // adress bar itself
            Rectangle {
                id: pill
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: Theme.pillRadius
                color: addressInput.activeFocus ? Theme.bg : Theme.surfaceHigh

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.durationFast
                    }
                }

                // Focus
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.color: Theme.accent
                    border.width: addressInput.activeFocus ? 1.5 : 0
                    Behavior on border.width {
                        NumberAnimation {
                            duration: Theme.durationFast
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 6

                    // icons
                    // could make clicable for context menu
                    LucideIcon {
                        size: 14
                        Layout.alignment: Qt.AlignVCenter
                        opacity: 0.7

                        source: {
                            const u = root.currentUrl;
                            if (u.startsWith("https://"))
                                return "qrc:/QT_Illuminate/ui/ui/icons/lock.svg";
                            if (u.startsWith("http://"))
                                return "qrc:/QT_Illuminate/ui/ui/icons/alert-triangle.svg";
                            return "qrc:/QT_Illuminate/ui/ui/icons/globe.svg";
                        }
                        color: {
                            const u = root.currentUrl;
                            if (u.startsWith("https://"))
                                return Theme.accent;
                            if (u.startsWith("http://"))
                                return Theme.danger;
                            return Theme.textMuted;
                        }
                    }

                    // url
                    TextInput {
                        id: addressInput
                        Layout.fillWidth: true
                        text: root.currentUrl
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeM
                        font.family: Theme.fontFamily
                        selectByMouse: true
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: {
                            if (activeFocus) {
                                suggestionsBox.highlighted = -1;
                                suggestTimer.restart();
                            }
                        }

onActiveFocusChanged: {
                        if (activeFocus) {
                            Qt.callLater(selectAll);
                            if (text.trim() !== "" && text !== "newtab://newtab")
                                suggestTimer.restart();
                        } else {
                            root.clearSuggestions();
                            text = root.currentUrl;
                        }
                    }

                        Keys.onDownPressed: {
                            if (suggestionModel.count > 0)
                                suggestionsBox.highlighted = Math.min(suggestionsBox.highlighted + 1, suggestionModel.count - 1);
                        }
                        Keys.onUpPressed: {
                            if (suggestionModel.count > 0)
                                suggestionsBox.highlighted = Math.max(suggestionsBox.highlighted - 1, -1);
                        }
                        Keys.onReturnPressed: {
                            if (suggestionsBox.highlighted >= 0) {
                                root.acceptSuggestion(suggestionsBox.highlighted);
                            } else if (text.trim() !== "") {
                                // capture before dropping focus: onActiveFocusChanged
                                // resets text to currentUrl ("" on the new tab page)
                                const input = text.trim();
                                root.clearSuggestions();
                                focus = false;
                                root.navigate(input);
                            }
                        }
                        Keys.onEscapePressed: {
                            if (suggestionModel.count > 0) {
                                root.clearSuggestions();
                            } else {
                                text = root.currentUrl;
                                focus = false;
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
                        source: root.isBookmarked ? "qrc:/QT_Illuminate/ui/ui/icons/star-filled.svg" : "qrc:/QT_Illuminate/ui/ui/icons/star.svg"
                        color: root.isBookmarked ? Theme.accent : (starHover.hovered ? Theme.text : Theme.textMuted)
                        Layout.alignment: Qt.AlignVCenter

                        HoverHandler {
                            id: starHover
                        }
                        TapHandler {
                            onTapped: root.toggleBookmark()
                        }
                    }
                }
            }

            // downloads
            LucideIcon {
                visible: root.downloadsPanel && root.downloadsPanel.downloadCount > 0
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/download.svg"
                color: (downloadsHover.hovered || (root.downloadsPanel && root.downloadsPanel.visible)) ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter

                HoverHandler {
                    id: downloadsHover
                }
                TapHandler {
                    onTapped: root.downloadsPanel && root.downloadsPanel.toggle()
                }

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

            // profile switcher button (avatar circle)
            Item {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 15
                    color: root.avatarColorFor(ProfileManager.activeProfile)
                    border.color: profileHover.hovered ? Theme.text : "transparent"
                    border.width: profileHover.hovered ? 1 : 0
                    Behavior on border.width {
                        NumberAnimation {
                            duration: Theme.durationFast
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: (ProfileManager.activeProfile && ProfileManager.activeProfile.name) ? ProfileManager.activeProfile.name.charAt(0).toUpperCase() : "⊕"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.family: Theme.fontFamily
                    color: "white"
                }

                HoverHandler {
                    id: profileHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: profileMenu.popup()
                }

                Menu {
                    id: profileMenu
                    popupType: Popup.Native

                    Repeater {
                        model: ProfileManager.profiles

                        MenuItem {
                            required property var modelData
                            width: 200
                            text: {
                                const nm = modelData.name || "Unnamed";
                                return modelData === ProfileManager.activeProfile ? nm + "  ✓" : nm;
                            }
                            enabled: modelData !== ProfileManager.activeProfile
                            onClicked: root.switchToProfile(modelData)
                        }
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Select Profile…"
                        onTriggered: root.openProfileSelector()
                    }
                }
            }

            // app menu
            LucideIcon {
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/more-vertical.svg"
                color: (menuHover.hovered || appMenu.visible) ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter

                HoverHandler {
                    id: menuHover
                }
                TapHandler {
                    onTapped: appMenu.popup()
                }

                Menu {
                    id: appMenu
                    popupType: Popup.Native

                    MenuItem {
                        text: "New Tab"
                        onTriggered: Browser.newTab()
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

                    MenuSeparator {}

                    Menu {
                        id: adBlockMenu
                        title: "Ad Blocker"
                        popupType: Popup.Native

                        // "example.com" for the current page; empty on internal pages
                        readonly property string site: root.currentUrl.startsWith("http") ? AdBlocker.siteKey(root.currentUrl) : ""
                        readonly property bool siteAllowed: site !== "" && AdBlocker.allowedSites.indexOf(site) >= 0

                        MenuItem {
                            enabled: false
                            text: AdBlocker.ruleCount > 0
                                ? AdBlocker.blockedCount.toLocaleString(Qt.locale(), "f", 0) + " blocked · "
                                    + AdBlocker.ruleCount.toLocaleString(Qt.locale(), "f", 0) + " filter rules"
                                : (AdBlocker.updating ? "Downloading filter lists…" : "No filter lists yet")
                        }

                        MenuSeparator {}

                        MenuItem {
                            text: AdBlocker.enabled ? "Turn Off Ad Blocking" : "Turn On Ad Blocking"
                            onTriggered: {
                                AdBlocker.enabled = !AdBlocker.enabled;
                                Browser.reload();
                            }
                        }
                        MenuItem {
                            text: adBlockMenu.site === "" ? "Allow Ads on This Site"
                                : (adBlockMenu.siteAllowed ? "Block Ads on " : "Allow Ads on ") + adBlockMenu.site
                            enabled: AdBlocker.enabled && adBlockMenu.site !== ""
                            onTriggered: {
                                AdBlocker.setSiteAllowed(root.currentUrl, !adBlockMenu.siteAllowed);
                                Browser.reload();
                            }
                        }

                        MenuSeparator {}

                        MenuItem {
                            text: AdBlocker.updating ? "Updating Filters…" : "Update Filters"
                            enabled: !AdBlocker.updating
                            onTriggered: AdBlocker.updateFilters()
                        }
                        MenuItem {
                            text: "Edit My Filters…"
                            onTriggered: AdBlocker.editCustomFilters()
                        }
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Developer Tools"
                        onTriggered: Browser.toggleDevTools()
                    }

                    MenuItem {
                        text: "Memory Usage"
                        onTriggered: Browser.newTab("illuminate://memory")
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Settings…"
                        onTriggered: root.openSettings()
                    }
                }
            }
        }
    }

    SuggestionBox {
        id: suggestionsBox
        anchors.top: toolbarBg.bottom
        x: pill.x + toolbarBg.x
        width: pill.width
        model: suggestionModel
        addressFocused: addressInput.activeFocus
        onSuggestionClicked: (index) => root.acceptSuggestion(index)
    }

    // load stipe
    Item {
        anchors.top: toolbarBg.bottom
        width: parent.width
        height: Theme.progressH

        // keep this strip the toolbar colour so it doesn't read as a
        // gap between the toolbar and whatever sits below (bookmarks bar)
        Rectangle {
            anchors.fill: parent
            color: Theme.toolbarBg
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            height: parent.height
            width: parent.width * (root.loadProgress / 100)
            color: Theme.accent
            opacity: (root.isLoading && root.loadProgress > 0 && root.loadProgress < 100) ? 1 : 0

            Behavior on width {
                NumberAnimation {
                    duration: 80
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.durationFast
                }
            }
        }
    }

    // sync when tab changes
    // why couldnt i do this in swift with webkit
    // i have no clue
    onCurrentUrlChanged: {
        if (!addressInput.activeFocus)
            addressInput.text = root.currentUrl;
    }
}
