import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// tabs
// oh tab.
Item {
    id: root

    required property var model
    required property int index

    property string tabTitle: model ? model.title : "New Tab"
    property string tabIconUrl: model ? model.iconUrl : ""
    property bool tabLoading: model ? model.loading : false
    property bool isActive: false
    property int tabCount: 1      // total tab count, for drag-reorder clamping
    property bool faviconFailed: false

    signal activated
    signal closeClicked
    signal reorderRequested(int targetIndex)   // drag crossed into a neighbour's slot

    readonly property int activeTopInset: 4   // gap above active tab body
    readonly property int inactiveTopInset: 7
    readonly property int inactiveBotInset: 4
    readonly property int shoulderW: Theme.tabCurveW   // width of the curved corner fill
    readonly property bool dragging: dragHandler.active
    onTabIconUrlChanged: faviconFailed = root.tabIconUrl === ""

    transform: Translate {
        id: dragTranslate
    }

    DragHandler {
        id: dragHandler
        yAxis.enabled: false
        target: null

        property real committedX: 0

        onActiveChanged: {
            committedX = 0;
            if (!active)
                dragTranslate.x = 0;
        }

        onTranslationChanged: {
            if (!active || root.width <= 0)
                return;
            let offset = translation.x - committedX;
            while (offset > root.width / 2 && root.index < root.tabCount - 1) {
                root.reorderRequested(root.index + 1);
                committedX += root.width;
                offset -= root.width;
            }
            while (offset < -root.width / 2 && root.index > 0) {
                root.reorderRequested(root.index - 1);
                committedX -= root.width;
                offset += root.width;
            }
            dragTranslate.x = offset;
        }
    }

    // main tab body
    Rectangle {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.isActive ? 0 : 1
        anchors.rightMargin: root.isActive ? 0 : 1
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: root.isActive ? root.activeTopInset : root.inactiveTopInset
        anchors.bottomMargin: root.isActive ? 0 : root.inactiveBotInset

        Behavior on anchors.topMargin {
            NumberAnimation {
                duration: Theme.durationFast
            }
        }
        Behavior on anchors.bottomMargin {
            NumberAnimation {
                duration: Theme.durationFast
            }
        }

        radius: Theme.tabRadius

        color: {
            if (root.isActive)
                return Theme.tabActive;
            if (hoverHandler.hovered)
                return Theme.tabHover;
            return Theme.tabInactive;
        }
        Behavior on color {
            ColorAnimation {
                duration: Theme.durationFast
            }
        }

        // when active clip onto others
        Rectangle {
            visible: root.isActive
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Theme.tabRadius
            height: Theme.tabRadius
            color: Theme.tabActive
        }
        Rectangle {
            visible: root.isActive
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: Theme.tabRadius
            height: Theme.tabRadius
            color: Theme.tabActive
        }

        // content row
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.isActive ? 12 : 10
            anchors.rightMargin: 4
            anchors.topMargin: 2
            anchors.bottomMargin: root.isActive ? 0 : 2
            spacing: 6

            // favicon & spinner
            Item {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: faviconImg
                    anchors.fill: parent
                    sourceSize.width: 32
                    sourceSize.height: 32
                    source: root.faviconFailed ? "" : root.tabIconUrl
                    visible: !root.tabLoading && root.tabIconUrl !== "" && !root.faviconFailed
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    onStatusChanged: if (status === Image.Error)
                        root.faviconFailed = true
                }

                LucideIcon {
                    anchors.centerIn: parent
                    visible: !root.tabLoading && (root.tabIconUrl === "" || root.faviconFailed)
                    source: "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                    color: Theme.textMuted
                    size: 13
                }

                Canvas {
                    anchors.fill: parent
                    visible: root.tabLoading
                    opacity: root.tabLoading ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.durationFast
                        }
                    }

                    // GPU transform
                    onVisibleChanged: if (visible)
                        requestPaint()
                    Component.onCompleted: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const cx = width / 2, cy = height / 2, r = width / 2 - 1.5;
                        ctx.strokeStyle = Theme.accent;
                        ctx.lineWidth = 2;
                        ctx.lineCap = "round";
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, 0, Math.PI * 1.3);
                        ctx.stroke();
                    }

                    RotationAnimation on rotation {
                        running: root.tabLoading
                        from: 0
                        to: 360
                        duration: 800
                        loops: Animation.Infinite
                    }
                }
            }

            // title
            Text {
                Layout.fillWidth: true
                text: root.tabTitle
                color: root.isActive ? Theme.text : Theme.textMuted
                font.pixelSize: Theme.fontSizeM
                font.family: Theme.fontFamily
                font.weight: root.isActive ? Font.Medium : Font.Normal
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.durationFast
                    }
                }
            }

            // close
            Rectangle {
                objectName: "closeButton"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                radius: 9
                color: closeHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"

                // show when hovered or active
                opacity: (root.isActive || hoverHandler.hovered) ? 1 : 0

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.durationFast
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.durationFast
                    }
                }

                LucideIcon {
                    anchors.centerIn: parent
                    source: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                    size: 10
                    color: closeHover.hovered ? Theme.text : Theme.textMuted
                }

                HoverHandler {
                    id: closeHover
                }
                TapHandler {
                    onTapped: root.closeClicked()
                }
            }
        }
    }

    // curved sholder
    Item {
        visible: root.isActive
        anchors.right: body.left
        anchors.bottom: body.bottom
        width: root.shoulderW
        height: root.shoulderW
        clip: true

        // bg-colour fill
        Rectangle {
            anchors.fill: parent
            color: Theme.tabStripBg
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            width: root.shoulderW * 2
            height: root.shoulderW * 2
            radius: root.shoulderW
            color: Theme.tabActive
        }
    }

    // right sholder
    Item {
        visible: root.isActive
        anchors.left: body.right
        anchors.bottom: body.bottom
        width: root.shoulderW
        height: root.shoulderW
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Theme.tabStripBg
        }
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: root.shoulderW * 2
            height: root.shoulderW * 2
            radius: root.shoulderW
            color: Theme.tabActive
        }
    }

    // interaction
    // hi lol
    HoverHandler {
        id: hoverHandler
    }
    TapHandler {
        onTapped: root.activated()
    }
}
