import QtQuick
import QtQuick.Window
import QT_Illuminate.ui

// window controls for windows and linux
Item {
    id: root

    implicitWidth:  Theme.sysControlW * 3
    implicitHeight: Theme.tabBarHeight

    readonly property var win: Window.window

    function toggleMaximize() {
        if (!win) return
        if (win.visibility === Window.Maximized) win.showNormal()
        else                                      win.showMaximized()
    }

    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        SysButton {
            icon:   "qrc:/QT_Illuminate/ui/ui/icons/minus.svg"
            action: function() { if (root.win) root.win.showMinimized() }
        }
        SysButton {
            icon:   "qrc:/QT_Illuminate/ui/ui/icons/square.svg"
            action: function() { root.toggleMaximize() }
        }
        SysButton {
            icon:    "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
            isClose: true
            action:  function() { if (root.win) root.win.close() }
        }
    }
}
