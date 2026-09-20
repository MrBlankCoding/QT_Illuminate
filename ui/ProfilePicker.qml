import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.Core
import QT_Illuminate.ui

ApplicationWindow {
    id: root
    width: 400
    height: 300
    visible: true
    title: "Select Profile"

    Component {
        id: browserWindowComp
        BrowserWindow {}
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10

        Text {
            text: "Select a Profile"
            font.pixelSize: 20
            Layout.alignment: Qt.AlignHCenter
        }

        ListView {
            id: profileListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: profileManager.profiles
            delegate: ItemDelegate {
                width: parent.width
                text: model.modelData.name
                onClicked: {
                     profileManager.activeProfile = model.modelData;
                     var win = browserWindowComp.createObject(null);
                     win.show();
                     root.visible = false;
                }
            }
        }

        Button {
            text: "Create New Profile"
            Layout.fillWidth: true
            onClicked: {
                profileManager.createProfile("New Profile");
            }
        }
    }
}
