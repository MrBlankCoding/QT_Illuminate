import QtQuick
import QtQuick.Window

Item {
    id: root

    DragHandler {
        target: null
        onActiveChanged: {
            const win = root.Window.window;
            if (active && win)
                win.startSystemMove();
        }
    }

    TapHandler {
        gesturePolicy: TapHandler.DragThreshold
        onTapCountChanged: {
            if (tapCount !== 2)
                return;
            const win = root.Window.window;
            if (!win)
                return;
            win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized();
        }
    }
}
