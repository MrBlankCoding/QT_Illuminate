import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

SettingsPage {
    heading: "Privacy"
    subtitle: "Decide what sites are allowed to store."

    SettingsCard {
        SettingItem {
            topDivider: false
            title: "Allow third-party cookies"
            description: "Lets sites you aren't on set cookies, which most need for embedded content and ads. Turn off to block them all; logins and widgets may break on some sites."

            SettingSwitch {
                id: thirdPartyCookiesSwitch
                checked: Prefs.thirdPartyCookiesEnabled
                onToggled: Prefs.thirdPartyCookiesEnabled = !thirdPartyCookiesSwitch.checked
            }
        }
    }

    Footnote {
        Layout.topMargin: 4
        text: "Applies to the active profile only and takes effect immediately, no restart needed."
    }
}
