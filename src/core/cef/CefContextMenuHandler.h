#pragma once

#include <include/cef_context_menu_handler.h>
#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QString>

#include "CefMainBrowserId.h"

class CefBrowserWrapper;

// CEF: QML wrapper for context menu parameters
class CefContextMenuParamsWrapper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl linkUrl READ linkUrl CONSTANT)
    // URL of the image/audio/video node under the cursor; what "Download Image"
    // has to fetch, and it can differ from linkUrl for linked media
    Q_PROPERTY(QUrl sourceUrl READ sourceUrl CONSTANT)
    Q_PROPERTY(QString selectedText READ selectedText CONSTANT)
    Q_PROPERTY(bool isContentEditable READ isContentEditable CONSTANT)
    Q_PROPERTY(int mediaType READ mediaType CONSTANT)
    Q_PROPERTY(int x READ x CONSTANT)
    Q_PROPERTY(int y READ y CONSTANT)

public:
    explicit CefContextMenuParamsWrapper(CefRefPtr<CefContextMenuParams> params, QObject *parent = nullptr);

    QUrl linkUrl() const { return m_linkUrl; }
    QUrl sourceUrl() const { return m_sourceUrl; }
    QString selectedText() const { return m_selectedText; }
    bool isContentEditable() const { return m_isContentEditable; }
    int mediaType() const { return m_mediaType; }
    int x() const { return m_x; }
    int y() const { return m_y; }

private:
    QUrl m_linkUrl;
    QUrl m_sourceUrl;
    QString m_selectedText;
    bool m_isContentEditable = false;
    int m_mediaType = 0;
    int m_x = 0;
    int m_y = 0;
};

class CefContextMenuHandlerImpl : public CefContextMenuHandler
{
public:
    explicit CefContextMenuHandlerImpl(CefBrowserWrapper *wrapper, CefMainBrowserId *mainBrowser);

    void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                             CefRefPtr<CefContextMenuParams> params,
                             CefRefPtr<CefMenuModel> model) override;

    bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefFrame> frame,
                              CefRefPtr<CefContextMenuParams> params,
                              int command_id,
                              EventFlags event_flags) override;

private:
    QPointer<CefBrowserWrapper> m_wrapper;
    // shared with the client; the DevTools browser keeps CEF's own context menu
    CefMainBrowserId *m_mainBrowser = nullptr;

    IMPLEMENT_REFCOUNTING(CefContextMenuHandlerImpl);
};
