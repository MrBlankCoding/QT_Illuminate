import QtQuick
import QtQuick.Controls
import QtWebEngine

Menu {
    id: root
    popupType: Popup.Native

    property WebEngineView webView: null
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
        onTriggered: root.webView.triggerWebAction(WebEngineView.CopyLinkToClipboard)
    }
    MenuItem {
        // rename based on what was clicked
        // this allows for downloads to be specific
        // download image etc
        readonly property int mediaType: root.request ? root.request.mediaType : ContextMenuRequest.MediaTypeNone
        readonly property bool hasLink: root.request && root.request.linkUrl.toString() !== ""

        text: mediaType === ContextMenuRequest.MediaTypeImage ? "Download Image" : mediaType === ContextMenuRequest.MediaTypeVideo ? "Download Video" : mediaType === ContextMenuRequest.MediaTypeAudio ? "Download Audio" : "Download Link"
        visible: mediaType === ContextMenuRequest.MediaTypeImage || mediaType === ContextMenuRequest.MediaTypeVideo || mediaType === ContextMenuRequest.MediaTypeAudio || hasLink
        onTriggered: {
            if (mediaType === ContextMenuRequest.MediaTypeImage)
                root.webView.triggerWebAction(WebEngineView.DownloadImageToDisk);
            else if (mediaType === ContextMenuRequest.MediaTypeVideo || mediaType === ContextMenuRequest.MediaTypeAudio)
                root.webView.triggerWebAction(WebEngineView.DownloadMediaToDisk);
            else
                root.webView.triggerWebAction(WebEngineView.DownloadLinkToDisk);
        }
    }
    MenuItem {
        text: "Copy"
        visible: root.request && root.request.selectedText !== ""
        onTriggered: root.webView.triggerWebAction(WebEngineView.Copy)
    }
    MenuItem {
        text: "Paste"
        visible: root.request && root.request.isContentEditable
        onTriggered: root.webView.triggerWebAction(WebEngineView.Paste)
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
