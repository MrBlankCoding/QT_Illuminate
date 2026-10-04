import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: root

    required property var model
    required property int index

    readonly property string tabTitle: model ? model.title : "New Tab"
    readonly property string tabIconUrl: model ? model.iconUrl : ""
    readonly property string tabUrl: model && model.url ? model.url.toString() : ""
    readonly property bool tabLoading: model ? model.loading : false
    readonly property bool tabSuspended: model ? model.suspended : false
    property bool isActive: false
    property int tabCount: 1      // total tab count, for drag-reorder clamping
    property bool faviconFailed: false

    visible: tabUrl !== "newtab://newtab"

    signal activated
    signal closeClicked
    signal reorderRequested(int targetIndex)   // drag crossed into a neighbour's slot

    readonly property bool dragging: dragHandler.active
    readonly property bool hovered: hoverHandler.hovered
    onTabIconUrlChanged: faviconFailed = false
    ListView.onPooled: {
        visible = false
        dragTranslate.y = 0
    }
    ListView.onReused: visible = root.tabUrl !== "newtab://newtab"

    transform: Translate {
        id: dragTranslate
    }

    DragHandler {
        id: dragHandler
        xAxis.enabled: false
        target: null
        property real committedY: 0

        onActiveChanged: {
            committedY = 0;
            if (!active)
                dragTranslate.y = 0;
        }

        onTranslationChanged: {
            const list = root.ListView.view;
            const step = root.height + (list ? list.spacing : 0);
            if (!active || step <= 0)
                return;
            let offset = translation.y - committedY;
            while (offset > step / 2 && root.index < root.tabCount - 1) {
                root.reorderRequested(root.index + 1);
                committedY += step;
                offset -= step;
            }
            while (offset < -step / 2 && root.index > 0) {
                root.reorderRequested(root.index - 1);
                committedY -= step;
                offset += step;
            }
            dragTranslate.y = offset;
        }
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Theme.radiusTab
        scale: tapHandler.pressed && !root.dragging ? Theme.pressScale : 1
        color: root.isActive ? Theme.itemActive
             : tapHandler.pressed ? Theme.itemPressed
             : root.hovered || root.dragging ? Theme.itemHover
             : "transparent"
        border.width: root.isActive ? 1 : 0
        border.color: Theme.itemActiveBorder

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        Behavior on scale { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space3 - 2
            anchors.rightMargin: Theme.space1 + 2
            spacing: Theme.space2 + 2
            Item {
                id: faviconBox
                Layout.preferredWidth: Theme.faviconSize
                Layout.preferredHeight: Theme.faviconSize
                Layout.alignment: Qt.AlignVCenter
                // sleeping tabs read as dimmed
                opacity: root.tabSuspended ? 0.45 : 1

                readonly property bool showFavicon: root.tabIconUrl !== "" && !root.faviconFailed

                Image {
                    anchors.fill: parent
                    sourceSize.width: Theme.faviconSize * 2
                    sourceSize.height: Theme.faviconSize * 2
                    source: root.faviconFailed ? "" : root.tabIconUrl
                    visible: !root.tabLoading && faviconBox.showFavicon
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    onStatusChanged: if (status === Image.Error) root.faviconFailed = true
                }

                LetterAvatar {
                    anchors.fill: parent
                    visible: !root.tabLoading && !faviconBox.showFavicon
                    url: root.tabUrl
                    title: root.tabTitle
                }

                Canvas {
                    anchors.fill: parent
                    // follows opacity so the fade-out gets to play
                    visible: opacity > 0
                    opacity: root.tabLoading ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

                    onVisibleChanged: if (visible) requestPaint()
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

            Text {
                Layout.fillWidth: true
                text: root.tabTitle
                // page-controlled: never interpret markup (it could load remote images)
                textFormat: Text.PlainText
                font.preferShaping: false
                color: root.isActive ? Theme.text : Theme.textMuted
                opacity: root.tabSuspended ? 0.7 : 1
                font.pixelSize: Theme.fontSizeM
                font.family: Theme.fontFamily
                font.weight: root.isActive ? Font.Medium : Font.Normal
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            }

            Rectangle {
                objectName: "closeButton"
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                radius: Theme.radiusS
                color: closeTap.pressed ? Theme.itemPressed : closeHover.hovered ? Theme.itemHover : "transparent"
                opacity: root.hovered && !root.dragging ? 1 : 0
                enabled: opacity > 0

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

                LucideIcon {
                    anchors.centerIn: parent
                    source: "qrc:/QT_Illuminate/ui/icons/x.svg"
                    size: 12
                    color: closeHover.hovered ? Theme.text : Theme.textMuted
                }

                HoverHandler {
                    id: closeHover
                }
                TapHandler {
                    id: closeTap
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.closeClicked()
                }
            }
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    TapHandler {
        id: tapHandler
        onTapped: if (!closeHover.hovered) root.activated()
    }

    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: root.closeClicked()
    }
}
