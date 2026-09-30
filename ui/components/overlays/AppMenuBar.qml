import QtQuick
import QtQuick.Controls
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: root

    readonly property bool showBar: !AppMenu.native
    readonly property var tree: showBar ? AppMenu.tree : []
    implicitHeight: showBar ? Theme.menuBarHeight : 0
    visible: showBar

    Rectangle {
        anchors.fill: parent
        color: Theme.tabStripBg
    }

    // what is left of the row is a drag handle
    DragHandler {
        target: null
        onActiveChanged: {
            if (active)
                root.Window.window.startSystemMove();
        }
    }

    component MenuButton: Item {
        id: button
        required property var node

        implicitWidth: label.implicitWidth + 2 * Theme.fontSizeM
        height: root.height

        Rectangle {
            anchors.fill: parent
            color: (hover.hovered || menu.visible) ? Theme.surfaceHigh : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: Theme.durationFast
                }
            }
        }

        Text {
            id: label
            anchors.centerIn: parent
            text: button.node ? button.node.label : ""
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeS
            color: Theme.text
        }

        HoverHandler {
            id: hover
        }
        TapHandler {
            onTapped: menu.popup()
        }

        Component {
            id: rowSource
            MenuItem {
                property var rowNode
                text: rowNode ? rowNode.label : ""
                enabled: rowNode ? rowNode.enabled : false
                checkable: rowNode ? rowNode.checked : false
                checked: rowNode ? rowNode.checked : false
                onTriggered: AppMenu.trigger(rowNode.id, rowNode.payload)
            }
        }

        Component {
            id: separatorSource
            MenuSeparator {
            }
        }

        Menu {
            id: menu
            popupType: Popup.Native
            function build(nodes) {
                for (let i = menu.built.length - 1; i >= 0; --i) {
                    menu.removeItem(menu.built[i]);
                    menu.built[i].destroy();
                }
                menu.built = [];

                const list = nodes || [];
                for (let i = 0; i < list.length; ++i) {
                    const node = list[i];
                    const item = (node.kind === "separator" ? separatorSource : rowSource).createObject(null);
                    if (!item)
                        continue;
                    if (node.kind !== "separator")
                        item.rowNode = node;

                    menu.insertItem(menu.built.length, item);
                    menu.built.push(item);
                }
            }

            property var built: []
            onAboutToShow: build(button.node ? button.node.children : [])
        }
    }

    Row {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Repeater {
            model: root.tree.length

            delegate: MenuButton {
                required property int index
                node: root.tree[index]
            }
        }
    }
}
