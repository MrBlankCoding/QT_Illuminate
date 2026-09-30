import QtQuick
import QT_Illuminate.ui

SettingsPage {
    heading: "Tabs"
    subtitle: "Manage memory use and closing behavior."

    SectionHeader {
        text: "Background tabs"
    }

    SettingsCard {
        SettingItem {
            topDivider: false
            title: "Unload inactive tabs"
            description: "Frees memory by discarding a background tab's page after it has been idle. The tab stays in the strip and reloads when you switch to it."

            SettingSwitch {
                id: autoUnloadSwitch
                checked: Prefs.autoUnloadEnabled
                onToggled: Prefs.autoUnloadEnabled = !autoUnloadSwitch.checked
            }
        }

        SettingItem {
            visible: Prefs.autoUnloadEnabled
            title: "Unload after"
            description: "How long a tab must sit in the background first."

            SettingCombo {
                id: unloadDelayCombo
                implicitWidth: 160
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
                value: Prefs.autoUnloadMinutes
                onActivated: Prefs.autoUnloadMinutes = unloadDelayCombo.currentValue
            }
        }
    }

    SectionHeader {
        text: "Closing"
    }

    SettingsCard {
        SettingItem {
            topDivider: false
            title: "Confirm before closing"
            description: "Asks before closing a window that has more than one tab open."

            SettingSwitch {
                id: confirmCloseSwitch
                checked: Prefs.confirmCloseMultipleTabs
                onToggled: Prefs.confirmCloseMultipleTabs = !confirmCloseSwitch.checked
            }
        }
    }
}
