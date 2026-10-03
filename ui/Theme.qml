pragma Singleton
import QtQuick
import QT_Illuminate.ui as UI

// central theme: every colour, size and duration the chrome uses lives here
QtObject {
    id: root

    // theme mode: "system" | "dark" | "light"
    readonly property string mode: (UI.Browser && UI.Browser.themeMode) ? UI.Browser.themeMode : "system"
    readonly property bool isDark: mode === "dark" || (mode === "system" && Application.styleHints.colorScheme === Qt.Dark)
    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property var paletteOptions: [
        { id: "blue", name: qsTr("Blue"), dark: "#89b4fa", light: "#2563eb" },
        { id: "violet", name: qsTr("Violet"), dark: "#cba6f7", light: "#7c3aed" },
        { id: "green", name: qsTr("Green"), dark: "#a6e3a1", light: "#15803d" },
        { id: "rose", name: qsTr("Rose"), dark: "#f38ba8", light: "#be123c" },
        { id: "orange", name: qsTr("Orange"), dark: "#fab387", light: "#c2410c" }
    ]
    readonly property var selectedPalette: {
        const selectedId = UI.Browser ? UI.Browser.themePalette : "blue";
        for (let i = 0; i < paletteOptions.length; ++i) {
            if (paletteOptions[i].id === selectedId)
                return paletteOptions[i];
        }
        return paletteOptions[0];
    }
    readonly property var activeCustomColors: UI.Browser ? UI.Browser.activeThemeColors : ({})
    readonly property var currentColorSet: root.colorSetFor(root.isDark)

    function defaultColorSet(dark) {
        return {
            accent: dark ? selectedPalette.dark : selectedPalette.light,
            bg: dark ? "#1e1e2e" : "#f5f5fa",
            surface: dark ? "#2a2a3d" : "#e8e9f0",
            surfaceHigh: dark ? "#33334d" : "#dbdce6",
            sidebarBg: dark ? "#16161f" : "#e4e5ee",
            text: dark ? "#cdd6f4" : "#1e1e2e",
            textMuted: dark ? "#6e7291" : "#7c7f99",
            border: dark ? "#3a3a55" : "#cfd1de",
            danger: "#f38ba8",
            progressBg: dark ? "#313244" : "#dadae8",
            shadow: "#000000"
        };
    }

    function colorSetFor(dark) {
        const scheme = dark ? "dark" : "light";
        const customSet = activeCustomColors ? activeCustomColors[scheme] : null;
        return customSet || root.defaultColorSet(dark);
    }

    function snapshotColors() {
        return {
            dark: Object.assign({}, root.colorSetFor(true)),
            light: Object.assign({}, root.colorSetFor(false))
        };
    }

    readonly property var colorRoles: [
        { key: "accent", label: qsTr("Accent") },
        { key: "bg", label: qsTr("Page background") },
        { key: "surface", label: qsTr("Surface") },
        { key: "surfaceHigh", label: qsTr("Raised surface") },
        { key: "sidebarBg", label: qsTr("Sidebar") },
        { key: "text", label: qsTr("Text") },
        { key: "textMuted", label: qsTr("Muted text") },
        { key: "border", label: qsTr("Borders") },
        { key: "danger", label: qsTr("Danger") },
        { key: "progressBg", label: qsTr("Progress track") },
        { key: "shadow", label: qsTr("Shadow") }
    ]

    // profile avatar choices
    readonly property var avatarColors: [
        "#4A90E2", "#2DA7A1", "#F3A43B", "#E86F67",
        "#8A6CFF", "#69B578", "#D96ACF"
    ]

    readonly property color accent:       currentColorSet.accent
    readonly property color accentDim:    Qt.tint(accent, isDark ? "#40000000" : "#40ffffff")
    readonly property color onAccent:     luma(accent) > 0.55 ? "#1e1e2e" : "#ffffff"

    function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

    // surfaces
    readonly property color bg:          currentColorSet.bg
    readonly property color surface:     currentColorSet.surface
    readonly property color surfaceHigh: currentColorSet.surfaceHigh

    // sidebar: the window background, which also shows around the content card
    readonly property color sidebarBg:   currentColorSet.sidebarBg
    // translucent fills read correctly over any sidebar tint (spaces, phase 4)
    readonly property color itemHover:   Qt.alpha(accent, isDark ? 0.08 : 0.06)
    readonly property color itemPressed: Qt.alpha(accent, isDark ? 0.14 : 0.11)
    readonly property color itemActive:  Qt.tint(surface, Qt.alpha(accent, isDark ? 0.20 : 0.12))
    readonly property color itemActiveBorder: Qt.alpha(accent, 0.25)
    readonly property color fieldBg:     Qt.alpha(text, isDark ? 0.07 : 0.05)

    // the rounded card the page sits in
    readonly property color cardBg:      bg
    readonly property color cardBorder:  Qt.alpha(border, isDark ? 0.24 : 0.42)
    readonly property color shadow:      Qt.alpha(currentColorSet.shadow, isDark ? 0.55 : 0.16)

    readonly property color text:        currentColorSet.text
    readonly property color textMuted:   currentColorSet.textMuted
    readonly property color border:      currentColorSet.border

    readonly property color danger:       currentColorSet.danger
    readonly property color progressBg:   currentColorSet.progressBg

    // spacing: 4px grid
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16

    // radii
    readonly property int radiusS:       6
    readonly property int radiusItem:    8           // sidebar buttons, fields
    readonly property int radiusTab:     10
    readonly property int radiusCard:    12          // the web content card
    readonly property int radiusCommand: 18          // floating command bar (phase 2)

    // window chrome
    readonly property int titleBarHeight: 40         // top strip of the sidebar; traffic lights centre in it
    readonly property int menuBarHeight: 28
    readonly property int trafficLightW: 78          // macOS traffic-light safe area
    readonly property int sysControlW:   40          // Windows/Linux control-button width
    readonly property int cardMargin:    8           // sidebar colour visible around the card

    // sidebar
    readonly property int sidebarPadding: 8
    readonly property int tabRowHeight:  36
    readonly property int iconButton:    28
    readonly property int faviconSize:   18
    readonly property int resizeHandleW: 8

    readonly property int progressH:     2

    // font
    readonly property string fontFamily:  Application.font.family
    readonly property int    fontSizeS:   11
    readonly property int    fontSizeM:   13
    readonly property int    fontSizeL:   15
    readonly property int    fontSizeXL:  17

    // animation
    readonly property int durationFast:   120        // hover
    readonly property int durationMid:    200        // panels
    readonly property int durationSlow:   300        // space transitions
    readonly property real pressScale:    0.97
}
