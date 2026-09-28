pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window
import QT_Illuminate.ui

ApplicationWindow {
    id: root
    width: 640
    height: 560
    minimumWidth: 520
    minimumHeight: 420
    title: "Settings"
    readonly property bool frameless: Qt.platform.os !== "osx"
    flags: frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window

    component DragHeader: Item {
        DragHandler {
            target: null
            onActiveChanged: {
                if (active)
                    root.startSystemMove();
            }
        }
        TapHandler {
            gesturePolicy: TapHandler.DragThreshold
            onTapCountChanged: {
                if (tapCount !== 2)
                    return;
                root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized();
            }
        }
    }

    // dropdown styled to match the app; Basic's default looks foreign here
    component SettingCombo: ComboBox {
        id: combo
        implicitWidth: 220
        implicitHeight: 30
        font.pixelSize: Theme.fontSizeM
        font.family: Theme.fontFamily

        // models are arrays of {name, value}; find by value, not identity
        function indexOfValue(v) {
            for (let i = 0; i < model.length; ++i) {
                if (model[i].value === v)
                    return i;
            }
            return -1;
        }

        background: Rectangle {
            radius: 6
            color: combo.hovered || combo.visualFocus ? Theme.surfaceHigh : Theme.surface
            border.color: Theme.border
            border.width: 1

            Behavior on color {
                ColorAnimation {
                    duration: Theme.durationFast
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                text: combo.displayText
                font: combo.font
                color: Theme.text
                elide: Text.ElideRight
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "⌄"
                font.pixelSize: Theme.fontSizeM
                font.family: Theme.fontFamily
                color: Theme.textMuted
            }
        }

        delegate: ItemDelegate {
            id: entry
            required property var modelData

            width: combo.width
            height: 30
            leftPadding: 10
            rightPadding: 10

            contentItem: Text {
                text: typeof entry.modelData === "string" ? entry.modelData : entry.modelData.name
                font: combo.font
                color: Theme.text
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            background: Rectangle {
                radius: 6
                color: entryHover.hovered ? Theme.accentDim : "transparent"
            }

            HoverHandler {
                id: entryHover
                cursorShape: Qt.PointingHandCursor
            }
        }

        popup: Popup {
            y: combo.height + 4
            width: combo.width
            implicitHeight: Math.min(contentItem.implicitHeight + 8, 260)
            padding: 4

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
                boundsBehavior: Flickable.StopAtBounds
                ScrollIndicator.vertical: ScrollIndicator {}
            }

            background: Rectangle {
                radius: 8
                color: Theme.surface
                border.color: Theme.border
                border.width: 1
            }
        }
    }

    // macOS-style toggle, hand rolled to match the rest of the chrome
    component SettingSwitch: Item {
        id: control
        property bool checked: false

        signal toggled

        implicitWidth: 40
        implicitHeight: 24

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: control.checked ? Theme.accent : Theme.surfaceHigh
            border.color: control.checked ? Theme.accent : Theme.border
            border.width: 1

            Behavior on color {
                ColorAnimation {
                    duration: Theme.durationFast
                }
            }
        }

        Rectangle {
            x: control.checked ? parent.width - width - 2 : 2
            y: 2
            width: 20
            height: 20
            radius: 10
            color: Theme.isDark ? "#f5f5fa" : "#ffffff"

            Behavior on x {
                NumberAnimation {
                    duration: Theme.durationFast
                }
            }
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: control.toggled()
        }
    }

    // title + optional description + the control underneath
    component SettingRow: ColumnLayout {
        id: row
        property string title
        property string description
        spacing: 6

        Text {
            text: row.title
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
            font.weight: Font.Medium
            color: Theme.text
        }

        Text {
            text: row.description
            visible: text.length > 0
            Layout.fillWidth: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeS
            color: Theme.textMuted
            wrapMode: Text.WordWrap
        }
    }

    component SectionTitle: Text {
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeS
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
        color: Theme.textMuted
    }

    component NavItem: Item {
        id: nav
        required property string label
        property int sectionIndex: -1
        readonly property bool selected: navRoot.currentIndex === nav.sectionIndex

        signal activated

        implicitHeight: 32

        Rectangle {
            anchors.fill: parent
            anchors.rightMargin: 8
            radius: 6
            color: nav.selected ? Theme.accentDim : (hover.hovered ? Theme.surfaceHigh : "transparent")

            Behavior on color {
                ColorAnimation {
                    duration: Theme.durationFast
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: nav.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
            font.weight: nav.selected ? Font.Medium : Font.Normal
            color: nav.selected ? Theme.text : Theme.textMuted
        }

        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: nav.activated()
        }
    }

    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.tabBarHeight
        visible: root.frameless
        color: Theme.tabStripBg

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.border
        }

        DragHeader {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: controls.left
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "Settings"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
            font.weight: Font.Medium
        }

        WindowControls {
            id: controls
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
        }
    }

    Item {
        id: navRoot
        property int currentIndex: 0
        readonly property var sections: ["Startup", "Search", "Privacy", "Tabs", "Shortcuts"]
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 150

        Column {
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 2

            Repeater {
                model: navRoot.sections

                delegate: NavItem {
                    required property var modelData
                    required property int index

                    label: modelData
                    sectionIndex: index
                    width: navRoot.width
                    onActivated: navRoot.currentIndex = sectionIndex
                }
            }
        }
    }

    // header is collapsed (height 0) on macOS, so this still aligns to the top
    ScrollView {
        id: scroll
        anchors.top: header.bottom
        anchors.left: navRoot.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: availableWidth

        StackLayout {
            id: pages
            width: scroll.availableWidth
            currentIndex: navRoot.currentIndex

            // ── startup and session ────────────────────────────────────────
            ColumnLayout {
                spacing: 18

                Item {
                    Layout.preferredHeight: 4
                }

                SectionTitle {
                    text: "On launch"
                }

                SettingRow {
                    title: "Open"
                    description: "What the first window shows when the app starts."
                    Layout.fillWidth: true

                    SettingCombo {
                        id: startupCombo
                        Layout.topMargin: 2
                        model: [
                            {
                                name: "New tab page",
                                value: "newtab"
                            },
                            {
                                name: "Homepage",
                                value: "homepage"
                            },
                            {
                                name: "Restore last session",
                                value: "session"
                            }
                        ]
                        textRole: "name"
                        valueRole: "value"
                        currentIndex: Math.max(0, indexOfValue(Prefs.startupBehavior))
                        onActivated: Prefs.startupBehavior = currentValue

                        Connections {
                            target: Prefs
                            function onStartupBehaviorChanged() {
                                startupCombo.currentIndex = Math.max(0, startupCombo.indexOfValue(Prefs.startupBehavior));
                            }
                        }
                    }
                }

                SettingRow {
                    title: "Homepage"
                    visible: Prefs.startupBehavior === "homepage"
                    Layout.preferredHeight: visible ? implicitHeight : 0
                    Layout.fillWidth: true
                    description: "Loaded when \"Open\" is set to Homepage."

                    TextField {
                        id: homepageField
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        Layout.maximumWidth: 320
                        placeholderText: "https://example.com"
                        placeholderTextColor: Theme.textMuted
                        font.pixelSize: Theme.fontSizeM
                        font.family: Theme.fontFamily
                        color: Theme.text
                        leftPadding: 0
                        rightPadding: 0
                        background: null
                        text: Prefs.homepageUrl
                        onEditingFinished: Prefs.homepageUrl = text

                        Connections {
                            target: Prefs
                            function onHomepageUrlChanged() {
                                if (!homepageField.activeFocus)
                                    homepageField.text = Prefs.homepageUrl;
                            }
                        }
                    }
                }

                SettingRow {
                    title: "Session"
                    Layout.fillWidth: true
                    description: "Tabs are written to the profile's session.json every time the app quits, and reopened only if \"Open\" is set to Restore last session."
                }
            }

            // ── search ──────────────────────────────────────────────────────
            ColumnLayout {
                spacing: 18

                Item {
                    Layout.preferredHeight: 4
                }

                SectionTitle {
                    text: "Address bar"
                }

                SettingRow {
                    title: "Search engine"
                    description: "Used whenever what you type in the address bar isn't a URL."
                    Layout.fillWidth: true

                    SettingCombo {
                        id: engineCombo
                        Layout.topMargin: 2
                        model: Prefs.searchEngines
                        textRole: "name"
                        valueRole: "id"
                        currentIndex: Math.max(0, indexOfValue(Prefs.searchEngineId))
                        onActivated: Prefs.searchEngineId = currentValue

                        Connections {
                            target: Prefs
                            function onSearchEngineChanged() {
                                engineCombo.currentIndex = Math.max(0, engineCombo.indexOfValue(Prefs.searchEngineId));
                            }
                        }
                    }
                }

                SettingRow {
                    title: "Custom search URL"
                    visible: Prefs.searchEngineId === "custom"
                    Layout.preferredHeight: visible ? implicitHeight : 0
                    Layout.fillWidth: true
                    description: "Put %s where the search terms go, e.g. https://duckduckgo.com/?q=%s"

                    TextField {
                        id: customSearchField
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        Layout.maximumWidth: 320
                        placeholderText: "https://duckduckgo.com/?q=%s"
                        placeholderTextColor: Theme.textMuted
                        font.pixelSize: Theme.fontSizeM
                        font.family: Theme.fontFamily
                        color: Theme.text
                        leftPadding: 0
                        rightPadding: 0
                        background: null
                        text: Prefs.customSearchUrl
                        onEditingFinished: Prefs.customSearchUrl = text

                        Connections {
                            target: Prefs
                            function onSearchEngineChanged() {
                                if (!customSearchField.activeFocus)
                                    customSearchField.text = Prefs.customSearchUrl;
                            }
                        }
                    }
                }

                SettingRow {
                    title: "Currently searching with"
                    Layout.fillWidth: true
                    description: Prefs.searchUrlTemplate()
                }
            }

            // ── privacy ─────────────────────────────────────────────────────
            ColumnLayout {
                spacing: 18

                Item {
                    Layout.preferredHeight: 4
                }

                SectionTitle {
                    text: "Cookies"
                }

                SettingRow {
                    title: "Allow third-party cookies"
                    description: "Lets sites you aren't on set cookies, which most sites need for embedded content and ads. Turn it off to block them all — expect logins and widgets to break on some sites."
                    Layout.fillWidth: true

                    SettingSwitch {
                        Layout.topMargin: 2
                        checked: Prefs.thirdPartyCookiesEnabled
                        onToggled: Prefs.thirdPartyCookiesEnabled = checked
                    }
                }

                SettingRow {
                    title: "Applies to"
                    Layout.fillWidth: true
                    description: "The active profile only, and takes effect immediately — no restart."
                }
            }

            // ── tabs ────────────────────────────────────────────────────────
            ColumnLayout {
                spacing: 18

                Item {
                    Layout.preferredHeight: 4
                }

                SectionTitle {
                    text: "Background tabs"
                }

                SettingRow {
                    title: "Unload inactive tabs"
                    description: "Frees memory by discarding a background tab's page after it has been idle for a while. The tab stays in the strip and reloads when you switch to it."
                    Layout.fillWidth: true

                    SettingSwitch {
                        Layout.topMargin: 2
                        checked: Prefs.autoUnloadEnabled
                        onToggled: Prefs.autoUnloadEnabled = checked
                    }
                }

                SettingRow {
                    title: "Unload after"
                    visible: Prefs.autoUnloadEnabled
                    Layout.preferredHeight: visible ? implicitHeight : 0
                    Layout.fillWidth: true
                    description: "How long a tab must sit in the background before it's unloaded."

                    SettingCombo {
                        id: unloadDelayCombo
                        Layout.topMargin: 2
                        model: [
                            {
                                name: "1 minute",
                                value: 1
                            },
                            {
                                name: "5 minutes",
                                value: 5
                            },
                            {
                                name: "10 minutes",
                                value: 10
                            },
                            {
                                name: "15 minutes",
                                value: 15
                            },
                            {
                                name: "30 minutes",
                                value: 30
                            },
                            {
                                name: "1 hour",
                                value: 60
                            }
                        ]
                        textRole: "name"
                        valueRole: "value"
                        currentIndex: Math.max(0, indexOfValue(Prefs.autoUnloadMinutes))
                        onActivated: Prefs.autoUnloadMinutes = currentValue

                        Connections {
                            target: Prefs
                            function onAutoUnloadChanged() {
                                unloadDelayCombo.currentIndex = Math.max(0, unloadDelayCombo.indexOfValue(Prefs.autoUnloadMinutes));
                            }
                        }
                    }
                }

                SectionTitle {
                    text: "Closing"
                    Layout.topMargin: 8
                }

                SettingRow {
                    title: "Confirm before closing"
                    description: "Asks before closing a window that has more than one tab open."
                    Layout.fillWidth: true

                    SettingSwitch {
                        Layout.topMargin: 2
                        checked: Prefs.confirmCloseMultipleTabs
                        onToggled: Prefs.confirmCloseMultipleTabs = checked
                    }
                }
            }

            // ── keyboard shortcuts ─────────────────────────────────────────
            ColumnLayout {
                id: shortcutPage
                spacing: 18

                // the registry hands back a flat catalog already ordered by
                // category; fold it into the groups the page renders
                readonly property var groups: {
                    const out = [];
                    for (let i = 0; i < Shortcuts.commands.length; ++i) {
                        const command = Shortcuts.commands[i];
                        const last = out.length > 0 ? out[out.length - 1] : null;
                        if (last !== null && last.title === command.category)
                            last.commands.push(command);
                        else
                            out.push({
                                title: command.category,
                                commands: [command]
                            });
                    }
                    return out;
                }

                Item {
                    Layout.preferredHeight: 4
                }

                SettingRow {
                    title: "Keyboard shortcuts"
                    description: "Click a shortcut to record a new combination. Backspace restores its default, Escape backs out, and a combination another command already uses will be refused."
                    Layout.fillWidth: true

                    PillButton {
                        Layout.topMargin: 2
                        visible: Shortcuts.hasCustomizations
                        Layout.preferredHeight: visible ? implicitHeight : 0
                        text: "Reset all"
                        leftPadding: 14
                        rightPadding: 14
                        topPadding: 6
                        bottomPadding: 6
                        fillColor: "transparent"
                        borderColor: Theme.border
                        textColor: Theme.text
                        hoverFillColor: Theme.surfaceHigh
                        onClicked: Shortcuts.resetAll()
                    }
                }

                Repeater {
                    model: shortcutPage.groups

                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6

                        SectionTitle {
                            text: modelData.title
                            Layout.topMargin: 8
                        }

                        Repeater {
                            model: modelData.commands

                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 12

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeM
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }

                                ShortcutField {
                                    commandId: modelData.id
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ResizeGrips {
        anchors.fill: parent
        visible: root.frameless && root.visibility === Window.Windowed
        z: 1000
        onRequestSystemResize: edges => root.startSystemResize(edges)
    }
}
