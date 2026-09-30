#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

class InternalPageManager : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(InternalPages)
    QML_SINGLETON

public:
    static InternalPageManager &instance();
    static InternalPageManager *create(QQmlEngine *, QJSEngine *);

    // Check if URL is an internal page (illuminate:// or newtab://)
    Q_INVOKABLE static bool isInternal(const QString &url);

    // Get QML resource component path for internal page
    Q_INVOKABLE static QString qmlSource(const QString &url);

    // tab title for internal page; empty falls back to "New Tab"
    Q_INVOKABLE static QString title(const QString &url);
};
