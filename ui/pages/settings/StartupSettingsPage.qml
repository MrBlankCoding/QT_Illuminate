import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

SettingsPage {
    heading: "Startup"
    subtitle: "Choose what you see when the app opens."

    SettingsCard {
        SettingItem {
            topDivider: false
            title: "Open"
            description: "What the first window shows when the app starts."

            SettingCombo {
                id: startupCombo
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
                currentIndex: Math.max(0, startupCombo.indexOfValue(Prefs.startupBehavior))
                onActivated: Prefs.startupBehavior = startupCombo.currentValue

                Connections {
                    target: Prefs
                    function onStartupBehaviorChanged() {
                        startupCombo.currentIndex = Math.max(0, startupCombo.indexOfValue(Prefs.startupBehavior));
                    }
                }
            }
        }

        SettingItem {
            visible: Prefs.startupBehavior === "homepage"
            title: "Homepage"
            description: "Loaded when Open is set to Homepage."

            SettingField {
                id: homepageField
                placeholderText: "https://example.com"
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
    }

    Footnote {
        Layout.topMargin: 4
        text: "Tabs are written to the profile's session.json every time the app quits, and reopened only if Open is set to Restore last session."
    }
}
