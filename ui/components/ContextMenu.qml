import QtQuick
import QtQuick.Controls
import QT_Illuminate.ui

Menu {
    id: root
    popupType: Popup.Native

    property CefBrowser webView: null
    property var request: null

    signal toggleDevTools
    signal inspectElement

    MenuItem {
        text: "Back"
        enabled: root.webView && root.webView.canGoBack
        onTriggered: root.webView.goBack()
    }
    MenuItem {
        text: "Forward"
        enabled: root.webView && root.webView.canGoForward
        onTriggered: root.webView.goForward()
    }
    MenuItem {
        text: "Reload"
        onTriggered: root.webView.reload()
    }
    MenuSeparator {}
    MenuItem {
        text: "Copy Link"
        visible: root.request && root.request.linkUrl.toString() !== ""
        onTriggered: root.webView.triggerWebAction(CefBrowser.CopyLinkToClipboard)
    }
    MenuItem {
        // rename based on what was clicked
        // this allows for downloads to be specific
        // download image etc
        readonly property int mediaType: root.request ? root.request.mediaType : 0
        readonly property bool hasLink: root.request && root.request.linkUrl.toString() !== ""

        text: mediaType === 1 ? "Download Image" : mediaType === 2 ? "Download Video" : mediaType === 3 ? "Download Audio" : "Download Link"
        visible: mediaType === 1 || mediaType === 2 || mediaType === 3 || hasLink
        onTriggered: {
            if (mediaType === 1)
                root.webView.triggerWebAction(CefBrowser.DownloadImageToDisk);
            else if (mediaType === 2 || mediaType === 3)
                root.webView.triggerWebAction(CefBrowser.DownloadMediaToDisk);
            else
                root.webView.triggerWebAction(CefBrowser.DownloadLinkToDisk);
        }
    }
    MenuItem {
        text: "Copy"
        visible: root.request && root.request.selectedText !== ""
        onTriggered: root.webView.triggerWebAction(CefBrowser.Copy)
    }
    MenuItem {
        text: "Paste"
        visible: root.request && root.request.isContentEditable
        onTriggered: root.webView.triggerWebAction(CefBrowser.Paste)
    }
    MenuSeparator {}

    MenuItem {
        text: "Inspect"
        onTriggered: root.inspectElement()
    }
    MenuItem {
        text: "Toggle Dev Tools"
        onTriggered: root.toggleDevTools()
    }
}
