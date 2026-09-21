import QtQuick
import QtQuick.Controls
import QtWebEngine

Menu {
    id: contextMenuRoot
    popupType: Popup.Native

    property var webView: null
    property var request: null

    MenuItem {
        text: "Back"
        enabled: contextMenuRoot.webView && contextMenuRoot.webView.canGoBack
        onTriggered: contextMenuRoot.webView.goBack()
    }
    MenuItem {
        text: "Forward"
        enabled: contextMenuRoot.webView && contextMenuRoot.webView.canGoForward
        onTriggered: contextMenuRoot.webView.goForward()
    }
    MenuItem {
        text: "Reload"
        onTriggered: contextMenuRoot.webView.reload()
    }
    MenuSeparator {}
    MenuItem {
        text: "Copy Link"
        visible: contextMenuRoot.request && contextMenuRoot.request.linkUrl.toString() !== ""
        onTriggered: contextMenuRoot.webView.triggerWebAction(WebEngineView.CopyLinkToClipboard)
    }
    MenuItem {
        // rename based on what was clicked
        // this allows for downloads to be specific
        // download image etc
        readonly property int mediaType: contextMenuRoot.request ? contextMenuRoot.request.mediaType : ContextMenuRequest.MediaTypeNone
        readonly property bool hasLink: contextMenuRoot.request && contextMenuRoot.request.linkUrl.toString() !== ""

        text: mediaType === ContextMenuRequest.MediaTypeImage ? "Download Image" : mediaType === ContextMenuRequest.MediaTypeVideo ? "Download Video" : mediaType === ContextMenuRequest.MediaTypeAudio ? "Download Audio" : "Download Link"
        visible: mediaType === ContextMenuRequest.MediaTypeImage || mediaType === ContextMenuRequest.MediaTypeVideo || mediaType === ContextMenuRequest.MediaTypeAudio || hasLink
        onTriggered: {
            if (mediaType === ContextMenuRequest.MediaTypeImage)
                contextMenuRoot.webView.triggerWebAction(WebEngineView.DownloadImageToDisk);
            else if (mediaType === ContextMenuRequest.MediaTypeVideo || mediaType === ContextMenuRequest.MediaTypeAudio)
                contextMenuRoot.webView.triggerWebAction(WebEngineView.DownloadMediaToDisk);
            else
                contextMenuRoot.webView.triggerWebAction(WebEngineView.DownloadLinkToDisk);
        }
    }
    MenuItem {
        text: "Copy"
        visible: contextMenuRoot.request && contextMenuRoot.request.selectedText !== ""
        onTriggered: contextMenuRoot.webView.triggerWebAction(WebEngineView.Copy)
    }
    MenuItem {
        text: "Paste"
        visible: contextMenuRoot.request && contextMenuRoot.request.isContentEditable
        onTriggered: contextMenuRoot.webView.triggerWebAction(WebEngineView.Paste)
    }
    MenuSeparator {}
    signal toggleDevTools

    MenuItem {
        text: "Toggle Dev Tools"
        onTriggered: toggleDevTools()
    }
}
