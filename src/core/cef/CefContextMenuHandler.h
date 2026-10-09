#pragma once

#include <include/cef_context_menu_handler.h>
#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QString>
#include <QVariantList>

#include "CefMainBrowserId.h"

class CefBrowserWrapper;

class CefContextMenuParamsWrapper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl linkUrl READ linkUrl CONSTANT)
    Q_PROPERTY(QUrl sourceUrl READ sourceUrl CONSTANT)
    Q_PROPERTY(QString selectedText READ selectedText CONSTANT)
    Q_PROPERTY(bool isContentEditable READ isContentEditable CONSTANT)
    Q_PROPERTY(int mediaType READ mediaType CONSTANT)
    Q_PROPERTY(int x READ x CONSTANT)
    Q_PROPERTY(int y READ y CONSTANT)
    // items extensions added to the page's menu: [{commandId, label, enabled}]
    Q_PROPERTY(QVariantList extensionItems READ extensionItems CONSTANT)

public:
    explicit CefContextMenuParamsWrapper(CefRefPtr<CefContextMenuParams> params,
                                         CefRefPtr<CefMenuModel> model,
                                         CefRefPtr<CefRunContextMenuCallback> callback,
                                         QObject *parent = nullptr);
    // an unanswered menu is cancelled, so Chrome never waits on it
    ~CefContextMenuParamsWrapper() override;

    QUrl linkUrl() const { return m_linkUrl; }
    QUrl sourceUrl() const { return m_sourceUrl; }
    QString selectedText() const { return m_selectedText; }
    bool isContentEditable() const { return m_isContentEditable; }
    int mediaType() const { return m_mediaType; }
    int x() const { return m_x; }
    int y() const { return m_y; }
    QVariantList extensionItems() const { return m_extensionItems; }

    // runs one of extensionItems
    Q_INVOKABLE void runCommand(int commandId);
    // the menu closed; cancels unless an item is picked straight after
    Q_INVOKABLE void dismiss();

private:
    void finish(int commandId);

    QUrl m_linkUrl;
    QUrl m_sourceUrl;
    QString m_selectedText;
    bool m_isContentEditable = false;
    int m_mediaType = 0;
    int m_x = 0;
    int m_y = 0;
    QVariantList m_extensionItems;
    CefRefPtr<CefRunContextMenuCallback> m_callback;
};

class CefContextMenuHandlerImpl : public CefContextMenuHandler
{
public:
    explicit CefContextMenuHandlerImpl(CefBrowserWrapper *wrapper, CefMainBrowserId *mainBrowser);

    // shows our QML menu in place of Chrome's
    bool RunContextMenu(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefContextMenuParams> params,
                        CefRefPtr<CefMenuModel> model,
                        CefRefPtr<CefRunContextMenuCallback> callback) override;

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
