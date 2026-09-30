import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

SettingsPage {
    heading: "Search"
    subtitle: "Control what happens when you type in the address bar."

    SettingsCard {
        SettingItem {
            topDivider: false
            title: "Search engine"
            description: "Used whenever what you type isn't a URL."

            SettingCombo {
                id: engineCombo
                model: Prefs.searchEngines
                textRole: "name"
                valueRole: "id"
                value: Prefs.searchEngineId
                onActivated: Prefs.searchEngineId = engineCombo.currentValue
            }
        }

        SettingItem {
            visible: Prefs.searchEngineId === "custom"
            title: "Custom search URL"
            description: "Put %s where the search terms go."

            SettingField {
                id: customSearchField
                placeholderText: "https://duckduckgo.com/?q=%s"
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

        SettingItem {
            title: "Show search suggestions"
            description: "Suggestions are fetched from Google as you type in the address bar."

            SettingSwitch {
                id: suggestionsSwitch
                checked: Prefs.searchSuggestionsEnabled
                onToggled: Prefs.searchSuggestionsEnabled = !suggestionsSwitch.checked
            }
        }
    }

    SectionHeader {
        text: "Currently searching with"
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        radius: 8
        color: Theme.surface

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            text: Prefs.searchUrlTemplate
            textFormat: Text.PlainText
            color: Theme.textMuted
            font.family: "Menlo"
            font.pixelSize: 11
            elide: Text.ElideMiddle
        }
    }
}
