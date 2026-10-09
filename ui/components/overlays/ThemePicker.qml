import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Popup {
    id: root

    property bool showArrow: true
    property real arrowOffset: 0

    readonly property var swatches: [
        { h: 0.600, s: 0.75, label: "Ocean"   },
        { h: 0.640, s: 0.80, label: "Blue"    },
        { h: 0.700, s: 0.70, label: "Iris"    },
        { h: 0.755, s: 0.65, label: "Violet"  },
        { h: 0.820, s: 0.60, label: "Plum"    },
        { h: 0.930, s: 0.72, label: "Pink"    },
        { h: 0.000, s: 0.80, label: "Red"     },
        { h: 0.040, s: 0.85, label: "Coral"   },
        { h: 0.080, s: 0.82, label: "Orange"  },
        { h: 0.125, s: 0.75, label: "Amber"   },
        { h: 0.210, s: 0.65, label: "Lime"    },
        { h: 0.370, s: 0.62, label: "Teal"    },
    ]

    readonly property int shadowPad: 18
    readonly property int swatchSize: 40
    readonly property int cols: 6

    // Generate a complete {dark, light} color set from a hue + saturation.
    // All 11 keys populated so the whole browser re-themes.
    function recolor(h, s) {
        // Chrome surfaces use a subtle tint of the hue — heavily desaturated
        const dCS = Math.min(s * 0.32, 0.28)   // dark chrome sat
        const lCS = Math.min(s * 0.22, 0.20)   // light chrome sat

        const dark = {
            accent:      Qt.hsla(h, s,           0.68, 1),
            bg:          Qt.hsla(h, dCS,          0.13, 1),
            surface:     Qt.hsla(h, dCS,          0.18, 1),
            surfaceHigh: Qt.hsla(h, dCS,          0.22, 1),
            sidebarBg:   Qt.hsla(h, dCS * 1.1,   0.09, 1),
            text:        Qt.hsla(h, 0.55,         0.88, 1),
            textMuted:   Qt.hsla(h, 0.14,         0.52, 1),
            border:      Qt.hsla(h, dCS * 1.4,   0.27, 1),
            danger:      "#f38ba8",
            progressBg:  Qt.hsla(h, dCS,          0.20, 1),
            shadow:      "#000000"
        }

        const light = {
            accent:      Qt.hsla(h, s,            0.38, 1),
            bg:          Qt.hsla(h, lCS,           0.97, 1),
            surface:     Qt.hsla(h, lCS,           0.92, 1),
            surfaceHigh: Qt.hsla(h, lCS,           0.87, 1),
            sidebarBg:   Qt.hsla(h, lCS * 1.15,   0.89, 1),
            text:        Qt.hsla(h, 0.28,          0.11, 1),
            textMuted:   Qt.hsla(h, 0.09,          0.46, 1),
            border:      Qt.hsla(h, lCS * 1.5,    0.80, 1),
            danger:      "#f38ba8",
            progressBg:  Qt.hsla(h, lCS,           0.85, 1),
            shadow:      "#000000"
        }

        return { dark: dark, light: light }
    }

    // Check if a swatch is the currently active theme by comparing its
    // generated accent hue against the active accent.
    function isActive(h) {
        const ac = Theme.accent
        if (ac.hslSaturation < 0.05) return false
        let diff = Math.abs(ac.hslHue - h)
        if (diff > 0.5) diff = 1.0 - diff
        return diff < 0.04
    }

    // Apply a swatch: create or reuse a single "ThemePicker" custom theme.
    function applyTheme(h, s) {
        const colors = root.recolor(h, s)
        const name = "Custom"
        if (Browser.activeCustomThemeId) {
            Browser.updateCustomTheme(Browser.activeCustomThemeId, name, colors)
        } else {
            Browser.createCustomTheme(name, colors)
        }
    }

    popupType: Popup.Window
    modal: false
    focus: true
    Component.onCompleted: PopupCloser.watch(root)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
    padding: shadowPad
    implicitWidth: 296 + shadowPad * 2
    implicitHeight: contentHeight + shadowPad * 2

    ChromeGlass {
        popupTarget: root
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 160; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast; easing.type: Easing.InQuad }
        NumberAnimation { property: "scale"; to: 0.97; duration: Theme.durationFast; easing.type: Easing.InQuad }
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
            anchors.margins: root.shadowPad
            radius: Theme.radiusCommand
            color: Theme.glassCardBg
            border.width: 1
            border.color: Theme.cardBorder
        }
        Shape {
            visible: root.showArrow
            x: card.x - 12
            y: card.y + (card.height - 29) / 2 + root.arrowOffset
            width: 14
            height: 29
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Theme.glassCardBg
                strokeColor: "transparent"
                PathSvg { path: "M14 0 L12 0 L2.6 12.1 Q0 14.5 2.6 16.9 L12 29 L14 29 Z" }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.cardBorder
                strokeWidth: 1
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M12 0 L2.6 12.1 Q0 14.5 2.6 16.9 L12 29" }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Light / Dark / System ──────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space4
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space4
            spacing: Theme.space2

            Repeater {
                model: [
                    { mode: "system", icon: "qrc:/QT_Illuminate/ui/icons/monitor.svg", label: "System" },
                    { mode: "light",  icon: "qrc:/QT_Illuminate/ui/icons/sun.svg",     label: "Light"  },
                    { mode: "dark",   icon: "qrc:/QT_Illuminate/ui/icons/moon.svg",    label: "Dark"   },
                ]

                delegate: Item {
                    id: modeBtn
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 52

                    readonly property bool active: Browser.themeMode === modeBtn.modelData.mode

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusItem
                        color: modeBtn.active ? Theme.itemActive
                             : modeHover.hovered ? Theme.itemHover : "transparent"
                        border.width: modeBtn.active ? 1 : 0
                        border.color: Theme.itemActiveBorder
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        enabled: false

                        LucideIcon {
                            Layout.alignment: Qt.AlignHCenter
                            size: 16
                            source: modeBtn.modelData.icon
                            color: modeBtn.active ? Theme.accent : Theme.textMuted
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modeBtn.modelData.label
                            font.pixelSize: Theme.fontSizeS
                            font.family: Theme.fontFamily
                            color: modeBtn.active ? Theme.text : Theme.textMuted
                        }
                    }

                    HoverHandler { id: modeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Browser.themeMode = modeBtn.modelData.mode }
                }
            }
        }

        // ── Divider ────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space3
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space4
            implicitHeight: 1
            color: Theme.cardBorder
        }

        // ── Swatches — explicit Grid, no Flow ──────────────────────
        // Two rows of 6. Fixed cell size avoids any layout ambiguity that
        // causes the second row's hit area to be clipped or misplaced.
        Column {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space3
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space4
            Layout.bottomMargin: Theme.space4
            spacing: Theme.space2

            Repeater {
                model: root.swatches.length / root.cols  // 2 rows

                delegate: Row {
                    id: swatchRow
                    required property int index
                    readonly property int rowStart: swatchRow.index * root.cols
                    width: parent.width
                    spacing: Theme.space2

                    Repeater {
                        model: root.cols

                        delegate: Item {
                            id: dot
                            required property int index
                            readonly property var swatch: root.swatches[swatchRow.rowStart + dot.index]
                            readonly property color dotColor: Qt.hsla(
                                dot.swatch.h, dot.swatch.s, Theme.isDark ? 0.65 : 0.48, 1)
                            readonly property bool active: root.isActive(dot.swatch.h)

                            width: (parent.width - Theme.space2 * (root.cols - 1)) / root.cols
                            height: root.swatchSize

                            ToolTip.visible: dotHover.hovered
                            ToolTip.text: dot.swatch.label
                            ToolTip.delay: 500

                            // Selection ring
                            Rectangle {
                                anchors.centerIn: parent
                                width: root.swatchSize - 2
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.width: dot.active ? 2 : 0
                                border.color: dot.dotColor
                                opacity: 0.6
                                Behavior on border.width { NumberAnimation { duration: 100 } }
                            }

                            // Dot circle
                            Rectangle {
                                anchors.centerIn: parent
                                width: dot.active ? 28 : dotHover.hovered ? 26 : 23
                                height: width
                                radius: width / 2
                                color: dot.dotColor
                                border.width: 2
                                border.color: Qt.alpha(Theme.cardBg, 0.7)
                                Behavior on width { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            }

                            HoverHandler { id: dotHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: root.applyTheme(dot.swatch.h, dot.swatch.s)
                            }
                        }
                    }
                }
            }
        }

        // ── Transparent background ─────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space4
            implicitHeight: 1
            color: Theme.cardBorder
        }

        Item {
            id: transparencyToggle
            Layout.fillWidth: true
            Layout.topMargin: Theme.space2
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space4
            Layout.bottomMargin: Theme.space1
            implicitHeight: 40

            readonly property bool active: Browser.transparentChrome

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusItem
                color: transparencyToggle.active ? Theme.itemActive
                     : trHover.hovered ? Theme.itemHover : "transparent"
                border.width: transparencyToggle.active ? 1 : 0
                border.color: Theme.itemActiveBorder
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space3
                spacing: Theme.space2
                enabled: false

                LucideIcon {
                    size: 15
                    source: "qrc:/QT_Illuminate/ui/icons/square.svg"
                    color: transparencyToggle.active ? Theme.accent : Theme.textMuted
                }
                Text {
                    Layout.fillWidth: true
                    text: "Transparent background"
                    font.pixelSize: Theme.fontSizeS
                    font.family: Theme.fontFamily
                    color: transparencyToggle.active ? Theme.text : Theme.textMuted
                }

                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 20
                    radius: height / 2
                    color: transparencyToggle.active ? Theme.accent : Theme.fieldBg
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                    Rectangle {
                        width: 16
                        height: 16
                        radius: height / 2
                        y: 2
                        x: transparencyToggle.active ? parent.width - width - 2 : 2
                        color: "#ffffff"
                        Behavior on x { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic } }
                    }
                }
            }

            HoverHandler { id: trHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Browser.transparentChrome = !Browser.transparentChrome }
        }

        // ── Reset to default ───────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space4
            implicitHeight: 1
            color: Theme.cardBorder
        }

        Item {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            implicitHeight: 36

            Text {
                anchors.centerIn: parent
                text: "Reset to default"
                font.pixelSize: Theme.fontSizeS
                font.family: Theme.fontFamily
                color: resetHover.hovered ? Theme.text : Theme.textMuted
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            }

            HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    Browser.activateCustomTheme("")
                    Browser.themePalette = "blue"
                }
            }
        }
    }
}
