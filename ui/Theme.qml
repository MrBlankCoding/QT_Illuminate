pragma Singleton
import QtQuick

// centrla theme
QtObject {
    // colours
    readonly property color bg:           "#1e1e2e"
    readonly property color surface:      "#2a2a3d"
    readonly property color surfaceHigh:  "#33334d"
    readonly property color tabActive:    "#1e1e2e"  
    readonly property color tabInactive:  "#252538"
    readonly property color tabHover:     "#2e2e45"
    readonly property color accent:       "#89b4fa"
    readonly property color accentDim:    "#4a7fca"
    readonly property color text:         "#cdd6f4"
    readonly property color textMuted:    "#6e7291"
    readonly property color border:       "#3a3a55"
    readonly property color danger:       "#f38ba8"
    readonly property color progressBg:   "#313244"

    // geometry
    readonly property int   tabBarHeight:  42          // full strip height
    readonly property int   tabHeight:     34          // tab pill height inside the strip
    readonly property int   tabMinWidth:   100
    readonly property int   tabMaxWidth:   240
    readonly property int   tabRadius:     8           // top corners only
    readonly property int   tabCurveW:     12          // width of the curved shoulder SVG region
    readonly property int   trafficLightW: 78          // macOS traffic-light safe area
    readonly property int   sysControlW:   46          // Windows/Linux control-button width

    // toolbar
    readonly property int   toolbarHeight: 44
    readonly property int   pillRadius:    20
    readonly property int   progressH:     3

    // font
    readonly property string fontFamily:  Qt.platform.os === "osx" ? Qt.application.font.family : "Segoe UI, sans-serif"
    readonly property int    fontSizeS:   11
    readonly property int    fontSizeM:   13

    // animation
    readonly property int durationFast:   120
    readonly property int durationMid:    200
}
