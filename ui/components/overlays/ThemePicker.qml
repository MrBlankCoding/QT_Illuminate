import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Popup {
    id: root

    property string editingScheme: Theme.isDark ? "dark" : "light"
    property string editingColorKey: ""

    popupType: Popup.Window
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 20
    width: 500
    height: 620
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)

    function editColor(key) {
        if (!Browser.activeCustomThemeId)
            return;
        root.editingColorKey = key;
        colorDialog.selectedColor = Theme.colorSetFor(root.editingScheme === "dark")[key];
        colorDialog.open();
    }

    function saveColor(color) {
        const colors = {
            dark: Object.assign({}, Browser.activeThemeColors.dark),
            light: Object.assign({}, Browser.activeThemeColors.light)
        };
        colors[root.editingScheme][root.editingColorKey] = color;
        const activeId = Browser.activeCustomThemeId;
        for (let i = 0; i < Browser.customThemes.length; ++i) {
            const theme = Browser.customThemes[i];
            if (theme.id === activeId) {
                Browser.updateCustomTheme(activeId, theme.name, colors);
                return;
            }
        }
    }

    function activeThemeName() {
        for (let i = 0; i < Browser.customThemes.length; ++i) {
            const theme = Browser.customThemes[i];
            if (theme.id === Browser.activeCustomThemeId)
                return theme.name;
        }
        return "";
    }

    ColorDialog {
        id: colorDialog
        title: qsTr("Choose a theme color")
        onAccepted: root.saveColor(selectedColor)
    }

    background: Item {
        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            blur: 26
            offset.y: 7
            color: Theme.shadow
        }
        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: 18
            radius: Theme.radiusCommand
            color: Theme.cardBg
            border.width: 1
            border.color: Theme.cardBorder
        }
    }

    contentItem: ColumnLayout {
        spacing: 9

        Text {
            text: qsTr("Theme")
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeL
            font.weight: Font.Medium
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { id: "system", label: qsTr("System") },
                    { id: "dark", label: qsTr("Dark") },
                    { id: "light", label: qsTr("Light") }
                ]

                delegate: Button {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.label
                    highlighted: modelData.id === Browser.themeMode
                    onClicked: Browser.themeMode = modelData.id
                }
            }
        }

        Text {
            text: qsTr("Presets")
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: Theme.paletteOptions

                delegate: Button {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.name
                    highlighted: !Browser.activeCustomThemeId && modelData.id === Browser.themePalette
                    onClicked: {
                        Browser.activateCustomTheme("");
                        Browser.themePalette = modelData.id;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: qsTr("Your themes")
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                Layout.fillWidth: true
            }

            TextField {
                id: themeName
                Layout.preferredWidth: 140
                placeholderText: qsTr("Theme name")
                Accessible.name: qsTr("Theme name")
            }

            Button {
                text: qsTr("Create")
                enabled: themeName.text.trim().length > 0
                onClicked: {
                    if (Browser.createCustomTheme(themeName.text, Theme.snapshotColors()))
                        themeName.clear();
                }
            }

            Button {
                text: qsTr("Rename")
                enabled: Browser.activeCustomThemeId !== "" && themeName.text.trim().length > 0
                onClicked: {
                    Browser.updateCustomTheme(Browser.activeCustomThemeId, themeName.text,
                                              Browser.activeThemeColors);
                    themeName.clear();
                }
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 92
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: parent.width
                spacing: 4

                Repeater {
                    model: Browser.customThemes

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6

                        Button {
                            Layout.fillWidth: true
                            text: modelData.name
                            highlighted: modelData.id === Browser.activeCustomThemeId
                            onClicked: {
                                Browser.activateCustomTheme(modelData.id);
                                themeName.text = modelData.name;
                            }
                        }

                        Button {
                            text: qsTr("Delete")
                            onClicked: Browser.deleteCustomTheme(modelData.id)
                        }
                    }
                }

                Text {
                    visible: Browser.customThemes.length === 0
                    text: qsTr("Create a theme to edit its colors.")
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeS
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: qsTr("Customize")
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                Layout.fillWidth: true
            }

            Button {
                text: qsTr("Dark")
                highlighted: root.editingScheme === "dark"
                onClicked: root.editingScheme = "dark"
            }

            Button {
                text: qsTr("Light")
                highlighted: root.editingScheme === "light"
                onClicked: root.editingScheme = "light"
            }
        }

        Grid {
            id: colorGrid
            columns: 2
            spacing: 5
            Layout.fillWidth: true
            Layout.preferredHeight: Math.ceil(Theme.colorRoles.length / columns) * 32
                + Math.max(0, Math.ceil(Theme.colorRoles.length / columns) - 1) * spacing
            readonly property real cellWidth: (width - spacing) / columns

            Repeater {
                model: Theme.colorRoles

                delegate: Button {
                    id: colorButton
                    required property var modelData
                    width: colorGrid.cellWidth
                    height: 32
                    enabled: Browser.activeCustomThemeId !== ""
                    contentItem: RowLayout {
                        spacing: 7

                        Rectangle {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            radius: 5
                            color: Theme.colorSetFor(root.editingScheme === "dark")[modelData.key]
                            border.width: 1
                            border.color: Theme.border
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: Theme.text
                            font: colorButton.font
                            elide: Text.ElideRight
                        }
                    }
                    onClicked: root.editColor(modelData.key)
                    Accessible.name: qsTr("Change %1 color").arg(modelData.label)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: Browser.activeCustomThemeId === ""
            text: qsTr("Select a custom theme above to edit its colors.")
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeS
        }
    }
}
