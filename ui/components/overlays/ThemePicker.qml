import QtQuick
import QtQuick.Controls.Basic
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
    property real customLightness: 0.68
    property bool orbitDirty: false
    readonly property int shadowPad: 18

    function recolor(h, s, selectedLightness) {
        const d = Math.min(s * 0.32, 0.28)
        const l = Math.min(s * 0.22, 0.20)
        const darkAccent = Theme.isDark ? Qt.hsla(h, s, selectedLightness, 1) : Qt.hsla(h, s, 0.68, 1)
        const lightAccent = Theme.isDark ? Qt.hsla(h, s, 0.38, 1) : Qt.hsla(h, s, selectedLightness, 1)
        return {
            dark: {
                accent: darkAccent, bg: Qt.hsla(h, d, 0.13, 1),
                surface: Qt.hsla(h, d, 0.18, 1), surfaceHigh: Qt.hsla(h, d, 0.22, 1),
                sidebarBg: Qt.hsla(h, d * 1.1, 0.09, 1), text: Qt.hsla(h, 0.55, 0.88, 1),
                textMuted: Qt.hsla(h, 0.14, 0.52, 1), border: Qt.hsla(h, d * 1.4, 0.27, 1),
                danger: "#f38ba8", progressBg: Qt.hsla(h, d, 0.20, 1), shadow: "#000000"
            },
            light: {
                accent: lightAccent, bg: Qt.hsla(h, l, 0.97, 1),
                surface: Qt.hsla(h, l, 0.92, 1), surfaceHigh: Qt.hsla(h, l, 0.87, 1),
                sidebarBg: Qt.hsla(h, l * 1.15, 0.89, 1), text: Qt.hsla(h, 0.28, 0.11, 1),
                textMuted: Qt.hsla(h, 0.09, 0.46, 1), border: Qt.hsla(h, l * 1.5, 0.80, 1),
                danger: "#f38ba8", progressBg: Qt.hsla(h, l, 0.85, 1), shadow: "#000000"
            }
        }
    }

    function setOrbitPoint(x, y) {
        const centerX = chromaCanvas.width / 2
        const centerY = chromaCanvas.height / 2
        const dx = x - centerX
        const dy = centerY - y
        const maxRadius = chromaCanvas.width * 0.47
        const distance = Math.sqrt(dx * dx + dy * dy)
        let hue = Math.atan2(dy, dx) / (Math.PI * 2)
        if (hue < 0)
            hue += 1

        customHue = hue
        customSaturation = Math.min(1, distance / maxRadius)
        customLightness = Theme.isDark ? 0.68 : 0.38
        orbitDirty = true
        Browser.previewSpaceThemeColors(recolor(customHue, customSaturation, customLightness))
    }

    function commitCustom() {
        Browser.setSpaceThemeColors(recolor(customHue, customSaturation, customLightness))
    }

    onOpened: {
        if (root.focusRouter)
            root.focusRouter.claimUiFocus("themePicker")
        const accent = Theme.accent
        customHue = accent.hslHue < 0 ? 0 : accent.hslHue
        customSaturation = accent.hslSaturation
        customLightness = accent.hslLightness
    }
    onClosed: {
        if (orbitDirty) {
            root.commitCustom()
            orbitDirty = false
        }
        if (root.focusRouter)
            root.focusRouter.releaseUiFocus("themePicker")
    }

    popupType: Popup.Window
    modal: false
    focus: true
    Component.onCompleted: PopupCloser.watch(root)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
    padding: shadowPad
    implicitWidth: 354 + shadowPad * 2

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
            radius: 18
            color: Theme.cardBg
            border.width: 1
            border.color: Theme.cardBorder
        }
        Shape {
            visible: root.showArrow
            x: card.x - 12; y: card.y + (card.height - 29) / 2 + root.arrowOffset
            width: 14; height: 29
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Theme.cardBg; strokeColor: "transparent"
                PathSvg { path: "M14 0 L12 0 L2.6 12.1 Q0 14.5 2.6 16.9 L12 29 L14 29 Z" }
            }
            ShapePath {
                fillColor: "transparent"; strokeColor: Theme.cardBorder; strokeWidth: 1
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M12 0 L2.6 12.1 Q0 14.5 2.6 16.9 L12 29" }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.topMargin: 14
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: qsTr("Color your space")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Browser.space ? Browser.space.name : qsTr("Current space")
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.topMargin: 12
            Layout.preferredHeight: 1
            color: Theme.cardBorder
        }

        Item {
            id: colorOrbit
            Layout.fillWidth: true
            Layout.preferredHeight: 294
            Layout.topMargin: 8
            Accessible.ignored: true

            Canvas {
                id: chromaCanvas
                width: Math.min(280, parent.width, parent.height)
                height: width
                anchors.centerIn: parent
                renderTarget: Canvas.FramebufferObject
                onPaint: {
                    const context = getContext("2d")
                    context.clearRect(0, 0, width, height)
                    const centerX = width / 2
                    const centerY = height / 2
                    const radius = Math.min(width, height) * 0.47
                    const step = 2
                    for (let y = 0; y < height; y += step) {
                        for (let x = 0; x < width; x += step) {
                            const dx = x - centerX
                            const dy = centerY - y
                            const distance = Math.sqrt(dx * dx + dy * dy)
                            if (distance > radius)
                                continue
                            let hue = Math.atan2(dy, dx) / (Math.PI * 2)
                            if (hue < 0)
                                hue += 1
                            const saturation = Math.min(1, distance / radius)
                            context.fillStyle = Qt.hsla(hue, saturation, 0.5, 1)
                            context.fillRect(x, y, step, step)
                        }
                    }
                }
            }

            Repeater {
                model: 24
                delegate: Rectangle {
                    required property int index
                    readonly property real angle: index * Math.PI * 2 / 24
                    width: index % 3 === 0 ? 3 : 2
                    height: index % 3 === 0 ? 6 : 3
                    radius: 1.5
                    x: chromaCanvas.x + chromaCanvas.width / 2 + Math.cos(angle) * (chromaCanvas.width * 0.49) - width / 2
                    y: chromaCanvas.y + chromaCanvas.height / 2 - Math.sin(angle) * (chromaCanvas.height * 0.49) - height / 2
                    rotation: index * 15
                    color: Qt.alpha(Theme.textMuted, 0.45)
                }
            }

            Repeater {
                model: [0.34, 0.68]
                delegate: Rectangle {
                    required property real modelData
                    width: chromaCanvas.width * modelData
                    height: width
                    x: chromaCanvas.x + (chromaCanvas.width - width) / 2
                    y: chromaCanvas.y + (chromaCanvas.height - height) / 2
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha("white", 0.34)
                }
            }

            Rectangle {
                id: orbitMarker
                width: 20; height: 20; radius: 10
                x: chromaCanvas.x + chromaCanvas.width / 2
                   + Math.cos(root.customHue * Math.PI * 2) * root.customSaturation * (chromaCanvas.width * 0.47) - width / 2
                y: chromaCanvas.y + chromaCanvas.height / 2
                   - Math.sin(root.customHue * Math.PI * 2) * root.customSaturation * (chromaCanvas.height * 0.47) - height / 2
                color: Qt.hsla(root.customHue, root.customSaturation, root.customLightness, 1)
                border.width: 2
                border.color: "white"
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha("#000000", 0.45)
                }
            }

            MouseArea {
                anchors.centerIn: chromaCanvas
                width: chromaCanvas.width
                height: chromaCanvas.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => {
                    forceActiveFocus()
                    root.setOrbitPoint(mouse.x, mouse.y)
                }
                onPositionChanged: mouse => {
                    if (pressed)
                        root.setOrbitPoint(mouse.x, mouse.y)
                }
                onReleased: {
                    root.commitCustom()
                    root.orbitDirty = false
                }
                activeFocusOnTab: true
                Accessible.role: Accessible.Slider
                Accessible.name: qsTr("Color orbit")
                Accessible.description: qsTr("Drag around the ring to change hue and move toward the center to reduce saturation")
                Keys.onPressed: event => {
                    const hueStep = 0.01
                    const saturationStep = 0.04
                    if (event.key === Qt.Key_Left)
                        root.customHue = (root.customHue - hueStep + 1) % 1
                    else if (event.key === Qt.Key_Right)
                        root.customHue = (root.customHue + hueStep) % 1
                    else if (event.key === Qt.Key_Up)
                        root.customSaturation = Math.min(1, root.customSaturation + saturationStep)
                    else if (event.key === Qt.Key_Down)
                        root.customSaturation = Math.max(0, root.customSaturation - saturationStep)
                    else
                        return
                    root.customLightness = Theme.isDark ? 0.68 : 0.38
                    root.commitCustom()
                    root.orbitDirty = false
                    event.accepted = true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14; Layout.rightMargin: 14
            Layout.topMargin: 10; Layout.bottomMargin: 12
            spacing: 4
            Item { Layout.fillWidth: true }
            Button {
                id: resetButton
                implicitWidth: 55; implicitHeight: 26
                text: qsTr("Reset")
                font.family: Theme.fontFamily
                font.pixelSize: 10
                onClicked: {
                    Browser.resetSpaceTheme()
                    orbitDirty = false
                    const accent = Theme.accent
                    customHue = accent.hslHue < 0 ? 0 : accent.hslHue
                    customSaturation = accent.hslSaturation
                    customLightness = accent.hslLightness
                }
                background: Rectangle {
                    radius: 7
                    color: resetButton.hovered ? Theme.itemHover : "transparent"
                }
                contentItem: Text {
                    text: resetButton.text
                    color: resetButton.hovered ? Theme.text : Theme.textMuted
                    font: resetButton.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Accessible.name: qsTr("Reset this space theme")
            }
        }
    }
}
