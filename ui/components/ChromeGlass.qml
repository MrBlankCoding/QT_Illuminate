import QtQuick
import QT_Illuminate.ui

QtObject {
    id: glass

    property var windowTarget: null   // a Window
    property var popupTarget: null    // a Popup
    // full-window vibrancy; only valid for rectangular windows (rounded panels
    // would show the blur as a square in their transparent padding)
    property bool vibrancy: true

    readonly property bool enabled: Theme.transparentChrome
    readonly property bool dark: Theme.isDark
    readonly property bool popupOpen: popupTarget ? popupTarget.opened : false
    readonly property bool windowVisible: windowTarget ? windowTarget.visible : false

    function apply() {
        if (popupTarget) {
            if (popupTarget.opened && popupTarget.contentItem)
                WindowHelper.setPopupTransparent(popupTarget.contentItem, enabled, dark, false);
        } else if (windowTarget && windowTarget.visible) {
            // only touch the native window while it is on screen; applying while
            // hidden can leave it non-key when shown again
            WindowHelper.setWindowTransparent(windowTarget, enabled, dark, vibrancy);
        }
    }

    onEnabledChanged: apply()
    onDarkChanged: apply()
    onPopupOpenChanged: apply()
    onWindowVisibleChanged: apply()
    Component.onCompleted: Qt.callLater(apply)
}
