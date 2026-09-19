#pragma once

#include <QObject>
#include <QUrl>
#include <QString>
#include "TabModel.h"

class BrowserController : public QObject
{
    Q_OBJECT

    // MOC revice tab model
    Q_PROPERTY(TabModel *tabModel    READ tabModel    CONSTANT)
    Q_PROPERTY(int       activeIndex READ activeIndex NOTIFY activeIndexChanged)
    Q_PROPERTY(QString   activeUrl      READ activeUrl      NOTIFY activeStateChanged)
    Q_PROPERTY(QString   activeTitle    READ activeTitle    NOTIFY activeStateChanged)
    Q_PROPERTY(bool      activeLoading  READ activeLoading  NOTIFY activeStateChanged)
    Q_PROPERTY(int       activeProgress READ activeProgress NOTIFY activeStateChanged)

public:
    explicit BrowserController(QObject *parent = nullptr);

    TabModel *tabModel()      const;
    int       activeIndex()   const;
    QString   activeUrl()     const;
    QString   activeTitle()   const;
    bool      activeLoading() const;
    int       activeProgress()const;

    // user actions
    Q_INVOKABLE void newTab(const QString &url = {});
    Q_INVOKABLE void closeTab(int index);
    Q_INVOKABLE void activateTab(int index);
    Q_INVOKABLE void cycleTab(int delta);
    Q_INVOKABLE void navigate(const QString &input);
    Q_INVOKABLE void reload();
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void goForward();
    Q_INVOKABLE void toggleDevTools();

    // state callbacks
    Q_INVOKABLE void onTitleChanged(int tabIndex, const QString &title);
    Q_INVOKABLE void onUrlChanged(int tabIndex, const QString &url);
    Q_INVOKABLE void onLoadingChanged(int tabIndex, bool loading);
    Q_INVOKABLE void onLoadProgressChanged(int tabIndex, int progress);
    Q_INVOKABLE void onIconUrlChanged(int tabIndex, const QString &iconUrl);
    Q_INVOKABLE void onNewWindowRequested(int tabIndex, const QString &url);

signals:
    void activeIndexChanged();
    void activeStateChanged();
    void loadRequested(int tabIndex, const QUrl &url);
    void navigationRequested(const QString &action);   // "back"|"forward"|"reload"|"devtools"

private:
    void rewireActiveTab();

    TabModel *m_model;
    // deleted and recreated every tab change
    QObject  *m_activeTabCtx = nullptr;
};
