import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Popup {
    id: root

    property bool showArrow: true
    property var focusRouter: null
    property real arrowOffset: 0
    property real customHue: 0.60
    property real customSaturation: 0.75
    property real intensity: 1.0
    readonly property int shadowPad: 18
    readonly property var palettes: [
        { id: "blue", name: qsTr("Blue"), color: "#4388f5" },
        { id: "violet", name: qsTr("Violet"), color: "#8057dc" },
        { id: "green", name: qsTr("Green"), color: "#21865b" },
        { id: "rose", name: qsTr("Rose"), color: "#cc456b" },
        { id: "orange", name: qsTr("Orange"), color: "#d66a22" },
        { id: "teal", name: qsTr("Teal"), color: "#168c91" },
        { id: "amber", name: qsTr("Amber"), color: "#a97805" },
        { id: "indigo", name: qsTr("Indigo"), color: "#4d5cce" },
        { id: "coral", name: qsTr("Coral"), color: "#d85646" },
        { id: "mint", name: qsTr("Mint"), color: "#348e73" },
        { id: "plum", name: qsTr("Plum"), color: "#a3439a" },
        { id: "slate", name: qsTr("Slate"), color: "#62758c" }
    ]

    function recolor(h, s) {
        const d = Math.min(s * 0.32, 0.28)
        const l = Math.min(s * 0.22, 0.20)
        return {
            dark: {
                accent: Qt.hsla(h, s, 0.68, 1), bg: Qt.hsla(h, d, 0.13, 1),
                surface: Qt.hsla(h, d, 0.18, 1), surfaceHigh: Qt.hsla(h, d, 0.22, 1),
                sidebarBg: Qt.hsla(h, d * 1.1, 0.09, 1), text: Qt.hsla(h, 0.55, 0.88, 1),
                textMuted: Qt.hsla(h, 0.14, 0.52, 1), border: Qt.hsla(h, d * 1.4, 0.27, 1),
                danger: "#f38ba8", progressBg: Qt.hsla(h, d, 0.20, 1), shadow: "#000000"
            },
            light: {
                accent: Qt.hsla(h, s, 0.38, 1), bg: Qt.hsla(h, l, 0.97, 1),
                surface: Qt.hsla(h, l, 0.92, 1), surfaceHigh: Qt.hsla(h, l, 0.87, 1),
                sidebarBg: Qt.hsla(h, l * 1.15, 0.89, 1), text: Qt.hsla(h, 0.28, 0.11, 1),
                textMuted: Qt.hsla(h, 0.09, 0.46, 1), border: Qt.hsla(h, l * 1.5, 0.80, 1),
                danger: "#f38ba8", progressBg: Qt.hsla(h, l, 0.85, 1), shadow: "#000000"
            }
        }
    }

    function applyCustom(h, s) {
        customHue = h < 0 ? 0 : h
        customSaturation = Math.max(0, Math.min(1, s))
        intensity = 1
        Browser.setSpaceThemeColors(recolor(customHue, customSaturation))
        hexInput.text = Qt.hsla(customHue, customSaturation, 0.5, 1).toString().toUpperCase()
    }

    function selectPalette(id, color) {
        const picked = Qt.color(color)
        customHue = picked.hslHue < 0 ? 0 : picked.hslHue
        customSaturation = picked.hslSaturation
        intensity = 1
        Browser.themePalette = id
        hexInput.text = picked.toString().toUpperCase()
    }

    function applyFieldPoint(x, y) {
        customHue = Math.max(0, Math.min(1, x / colorField.width))
        customSaturation = 1 - Math.max(0, Math.min(1, y / colorField.height))
        applyTimer.restart()
    }

    function commitCustom() {
        Browser.setSpaceThemeColors(recolor(customHue, customSaturation * intensity))
    }

    onOpened: {
        if (root.focusRouter)
            root.focusRouter.claimUiFocus("themePicker");
        const accent = Theme.accent
        customHue = accent.hslHue < 0 ? 0 : accent.hslHue
        customSaturation = accent.hslSaturation
        intensity = 1
        hexInput.text = accent.toString().toUpperCase()
    }
    onClosed: if (root.focusRouter) root.focusRouter.releaseUiFocus("themePicker")

    popupType: Popup.Window
    modal: false
    focus: true
    Component.onCompleted: PopupCloser.watch(root)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
    padding: shadowPad
    implicitWidth: 326 + shadowPad * 2
    implicitHeight: contentHeight + shadowPad * 2

    ChromeGlass { popupTarget: root }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast; easing.type: Easing.InQuad }
        NumberAnimation { property: "scale"; to: 0.98; duration: Theme.durationFast; easing.type: Easing.InQuad }
    }

    background: Item {
        RectangularShadow { anchors.fill: card; radius: card.radius; blur: 24; offset.y: 6; color: Theme.shadow }
        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: root.shadowPad
            radius: 16
            color: Theme.glassCardBg
            border.width: 1
            border.color: Theme.cardBorder
        }
        Shape {
            visible: root.showArrow
            x: card.x - 12; y: card.y + (card.height - 29) / 2 + root.arrowOffset
            width: 14; height: 29
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Theme.glassCardBg; strokeColor: "transparent"
                PathSvg { path: "M14 0 L12 0 L2.6 12.1 Q0 14.5 2.6 16.9 L12 29 L14 29 Z" }
            }
            ShapePath {
                fillColor: "transparent"; strokeColor: Theme.cardBorder; strokeWidth: 1
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M12 0 L2.6 12.1 Q0 14.5 2.6 16.9 L12 29" }
            }
        }
    }

    Timer {
        id: applyTimer
        interval: 45
        repeat: false
        onTriggered: Browser.previewSpaceThemeColors(root.recolor(root.customHue, root.customSaturation * root.intensity))
    }

    ColorDialog {
        id: colorDialog
        title: qsTr("Choose a theme color")
        selectedColor: Theme.accent
        onAccepted: root.applyCustom(selectedColor.hslHue, selectedColor.hslSaturation)
    }

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 17; Layout.rightMargin: 17; Layout.topMargin: 15
            spacing: 9
            Rectangle {
                Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 9
                color: Qt.alpha(Theme.accent, 0.14)
                border.color: Qt.alpha(Theme.accent, 0.25); border.width: 1
                Rectangle { width: 12; height: 12; radius: 6; anchors.centerIn: parent; color: Theme.accent }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                Text { text: qsTr("Theme"); color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
                Text {
                    text: Browser.space ? Browser.space.name : qsTr("Current space")
                    color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: 10
                }
            }
            Row {
                spacing: 2
                Repeater {
                    model: [
                        { id: "system", icon: "qrc:/QT_Illuminate/ui/icons/monitor.svg", hint: qsTr("Automatic") },
                        { id: "light", icon: "qrc:/QT_Illuminate/ui/icons/sun.svg", hint: qsTr("Light") },
                        { id: "dark", icon: "qrc:/QT_Illuminate/ui/icons/moon.svg", hint: qsTr("Dark") }
                    ]
                    delegate: Item {
                        id: modeButton
                        required property var modelData
                        width: 30; height: 30
                        readonly property bool selected: Browser.themeMode === modelData.id
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: modeButton.selected ? Theme.itemActive : (modeHover.hovered ? Theme.itemHover : "transparent")
                            border.width: modeButton.selected ? 1 : 0; border.color: Theme.itemActiveBorder
                        }
                        LucideIcon {
                            anchors.centerIn: parent; size: 14; source: modeButton.modelData.icon
                            color: modeButton.selected ? Theme.accent : Theme.textMuted
                        }
                        HoverHandler { id: modeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Browser.themeMode = modeButton.modelData.id }
                        ToolTip.visible: modeHover.hovered
                        ToolTip.text: modeButton.modelData.hint
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.leftMargin: 17; Layout.rightMargin: 17
            Layout.topMargin: 13; Layout.preferredHeight: 1; color: Theme.cardBorder
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 17; Layout.rightMargin: 17; Layout.topMargin: 12
            Text {
                Layout.fillWidth: true; text: qsTr("Color"); color: Theme.text
                font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold
            }
            Text { text: qsTr("12 presets"); color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: 10 }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 17; Layout.rightMargin: 17; Layout.topMargin: 9
            columns: 6; rowSpacing: 8; columnSpacing: 6
            Repeater {
                model: root.palettes
                delegate: Item {
                    id: swatch
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: 29
                    readonly property bool selected: Browser.themePalette === modelData.id && !Object.keys(Browser.activeThemeColors || {}).length
                    Rectangle {
                        anchors.centerIn: parent
                        width: 23; height: 23; radius: 12
                        color: swatch.modelData.color
                        border.width: swatch.selected ? 2 : 0
                        border.color: Theme.text
                        scale: swatchHover.hovered ? 1.08 : 1
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        Rectangle {
                            visible: swatch.selected
                            anchors.centerIn: parent
                            width: 7; height: 7; radius: 4; color: "white"
                            border.width: 1; border.color: Qt.darker(swatch.modelData.color, 1.2)
                        }
                    }
                    HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.selectPalette(swatch.modelData.id, swatch.modelData.color) }
                    ToolTip.visible: swatchHover.hovered
                    ToolTip.text: swatch.modelData.name
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("%1 theme color").arg(swatch.modelData.name)
                    Accessible.selected: swatch.selected
                }
            }
        }

        Item {
            id: colorField
            Layout.fillWidth: true
            Layout.leftMargin: 17; Layout.rightMargin: 17; Layout.topMargin: 10
            implicitHeight: 116

            Canvas {
                anchors.fill: parent
                renderTarget: Canvas.FramebufferObject
                onPaint: {
                    const ctx = getContext("2d")
                    const step = 2
                    for (let x = 0; x < width; x += step) {
                        const hue = x / width
                        for (let y = 0; y < height; y += step) {
                            const saturation = 1 - y / height
                            ctx.fillStyle = Qt.hsla(hue, saturation, 0.5, 1)
                            ctx.fillRect(x, y, step, step)
                        }
                    }
                }
            }
            Rectangle {
                anchors.fill: parent; radius: 8; color: "transparent"
                border.width: 1; border.color: Qt.alpha(Theme.text, 0.22)
            }
            Rectangle {
                x: Math.max(5, Math.min(parent.width - width - 5, root.customHue * parent.width - width / 2))
                y: Math.max(5, Math.min(parent.height - height - 5, (1 - root.customSaturation) * parent.height - height / 2))
                width: 18; height: 18; radius: 9
                color: Qt.hsla(root.customHue, root.customSaturation, 0.5, 1)
                border.width: 2; border.color: "white"
                Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: "white" }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPressed: mouse => root.applyFieldPoint(mouse.x, mouse.y)
                onPositionChanged: mouse => { if (pressed) root.applyFieldPoint(mouse.x, mouse.y) }
                onReleased: root.commitCustom()
                Accessible.role: Accessible.Slider
                Accessible.name: qsTr("Theme hue and saturation")
                Accessible.description: qsTr("Move horizontally to change hue and vertically to change saturation")
                activeFocusOnTab: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Left) root.customHue = Math.max(0, root.customHue - 0.01)
                    else if (event.key === Qt.Key_Right) root.customHue = Math.min(1, root.customHue + 0.01)
                    else if (event.key === Qt.Key_Up) root.customSaturation = Math.min(1, root.customSaturation + 0.03)
                    else if (event.key === Qt.Key_Down) root.customSaturation = Math.max(0, root.customSaturation - 0.03)
                    else return
                    applyTimer.restart()
                    root.commitCustom()
                    event.accepted = true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 17; Layout.rightMargin: 17; Layout.topMargin: 11
            spacing: 9
            Text { text: qsTr("Intensity"); color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: 10 }
            Slider {
                id: intensitySlider
                Layout.fillWidth: true
                property bool wasPressed: false
                from: 0.45; to: 1
                value: root.intensity
                onMoved: { root.intensity = value; applyTimer.restart() }
                onPressedChanged: {
                    if (pressed)
                        wasPressed = true
                    else if (wasPressed) {
                        wasPressed = false
                        root.commitCustom()
                    }
                }
                Accessible.name: qsTr("Theme color intensity")
            }
            Rectangle {
                Layout.preferredWidth: 20; Layout.preferredHeight: 20; radius: 7
                color: Qt.hsla(root.customHue, root.customSaturation * root.intensity, 0.5, 1)
                border.width: 1; border.color: Theme.cardBorder
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 17; Layout.rightMargin: 17; Layout.topMargin: 7
            TextField {
                id: hexInput
                Layout.fillWidth: true; implicitHeight: 30
                placeholderText: qsTr("# Hex color")
                color: Theme.text; placeholderTextColor: Theme.textMuted
                font.family: Theme.fontFamily; font.pixelSize: 11
                selectByMouse: true
                background: Rectangle { radius: 7; color: Theme.fieldBg; border.width: 1; border.color: Theme.cardBorder }
                onAccepted: {
                    if (/^#[0-9a-fA-F]{6}$/.test(text)) {
                        const picked = Qt.color(text)
                        root.applyCustom(picked.hslHue, picked.hslSaturation)
                    }
                }
            }
            Item {
                Layout.preferredWidth: 30; Layout.preferredHeight: 30
                Rectangle { anchors.fill: parent; radius: 7; color: colorButtonHover.hovered ? Theme.itemHover : Theme.fieldBg; border.width: 1; border.color: Theme.cardBorder }
                LucideIcon { anchors.centerIn: parent; source: "qrc:/QT_Illuminate/ui/icons/square.svg"; size: 14; color: Theme.textMuted }
                HoverHandler { id: colorButtonHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: colorDialog.open() }
                ToolTip.visible: colorButtonHover.hovered
                ToolTip.text: qsTr("Choose a color")
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Open system color picker")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 17; Layout.rightMargin: 17; Layout.topMargin: 10; Layout.bottomMargin: 12
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    text: qsTr("Translucent sidebar")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Let your desktop show through the browser chrome")
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                }
            }
            Item {
                Layout.preferredWidth: 38; Layout.preferredHeight: 24
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: Browser.transparentChrome ? Theme.accent : Theme.fieldBg
                    border.width: 1
                    border.color: Browser.transparentChrome ? Qt.alpha(Theme.accent, 0.55) : Theme.cardBorder
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                Rectangle {
                    width: 18; height: 18; radius: 9; y: 3
                    x: Browser.transparentChrome ? 17 : 3
                    color: "white"
                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Browser.transparentChrome = !Browser.transparentChrome }
                Accessible.role: Accessible.Switch
                Accessible.name: qsTr("Translucent sidebar")
                Accessible.checked: Browser.transparentChrome
            }
            Item {
                Layout.preferredWidth: 76; Layout.preferredHeight: 25
                Text {
                    anchors.centerIn: parent; text: qsTr("Reset")
                    color: resetHover.hovered ? Theme.text : Theme.textMuted
                    font.family: Theme.fontFamily; font.pixelSize: 10
                }
                HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { Browser.resetSpaceTheme(); root.intensity = 1 } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Reset this space theme")
            }
        }
    }
}
