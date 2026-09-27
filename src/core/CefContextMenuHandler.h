#pragma once

#include <include/cef_context_menu_handler.h>
#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QString>

class CefBrowserWrapper;

// CEF: QML wrapper for context menu parameters
class CefContextMenuParamsWrapper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl linkUrl READ linkUrl CONSTANT)
    Q_PROPERTY(QString selectedText READ selectedText CONSTANT)
    Q_PROPERTY(bool isContentEditable READ isContentEditable CONSTANT)
    Q_PROPERTY(int mediaType READ mediaType CONSTANT)
    Q_PROPERTY(int x READ x CONSTANT)
    Q_PROPERTY(int y READ y CONSTANT)

public:
    explicit CefContextMenuParamsWrapper(CefRefPtr<CefContextMenuParams> params, QObject *parent = nullptr);

    QUrl linkUrl() const { return m_linkUrl; }
    QString selectedText() const { return m_selectedText; }
    bool isContentEditable() const { return m_isContentEditable; }
    int mediaType() const { return m_mediaType; }
    int x() const { return m_x; }
    int y() const { return m_y; }

private:
    QUrl m_linkUrl;
    QString m_selectedText;
    bool m_isContentEditable = false;
    int m_mediaType = 0;
    int m_x = 0;
    int m_y = 0;
};

class CefContextMenuHandlerImpl : public CefContextMenuHandler
{
public:
    explicit CefContextMenuHandlerImpl(CefBrowserWrapper *wrapper);

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

    IMPLEMENT_REFCOUNTING(CefContextMenuHandlerImpl);
};
