import QtQuick

Item {
    id: resizeGripsRoot

    property int edgeGrip: 6
    property int cornerGrip: 10

    // Expose a signal or property to handle system resize requests
    signal requestSystemResize(int edges)

    MouseArea { // left
        height: parent.height - resizeGripsRoot.cornerGrip * 2
        width: resizeGripsRoot.edgeGrip
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        cursorShape: Qt.SizeHorCursor
        onPressed: resizeGripsRoot.requestSystemResize(Qt.LeftEdge)
    }
    MouseArea { // right
        height: parent.height - resizeGripsRoot.cornerGrip * 2
        width: resizeGripsRoot.edgeGrip
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        cursorShape: Qt.SizeHorCursor
        onPressed: resizeGripsRoot.requestSystemResize(Qt.RightEdge)
    }
    MouseArea { // bottom
        width: parent.width - resizeGripsRoot.cornerGrip * 2
        height: resizeGripsRoot.edgeGrip
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        cursorShape: Qt.SizeVerCursor
        onPressed: resizeGripsRoot.requestSystemResize(Qt.BottomEdge)
    }
    MouseArea { // top-left corner
        width: resizeGripsRoot.cornerGrip
        height: resizeGripsRoot.cornerGrip
        anchors.top: parent.top
        anchors.left: parent.left
        cursorShape: Qt.SizeFDiagCursor
        onPressed: resizeGripsRoot.requestSystemResize(Qt.TopEdge | Qt.LeftEdge)
    }
    MouseArea { // top-right corner
        width: resizeGripsRoot.cornerGrip
        height: resizeGripsRoot.cornerGrip
        anchors.top: parent.top
        anchors.right: parent.right
        cursorShape: Qt.SizeBDiagCursor
        onPressed: resizeGripsRoot.requestSystemResize(Qt.TopEdge | Qt.RightEdge)
    }
    MouseArea { // bottom-left corner
        width: resizeGripsRoot.cornerGrip
        height: resizeGripsRoot.cornerGrip
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        cursorShape: Qt.SizeBDiagCursor
        onPressed: resizeGripsRoot.requestSystemResize(Qt.BottomEdge | Qt.LeftEdge)
    }
    MouseArea { // bottom-right corner
        width: resizeGripsRoot.cornerGrip
        height: resizeGripsRoot.cornerGrip
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        cursorShape: Qt.SizeFDiagCursor
        onPressed: resizeGripsRoot.requestSystemResize(Qt.BottomEdge | Qt.RightEdge)
    }
}
