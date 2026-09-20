#pragma once

#include <QObject>
#include <QUrl>
#include <QString>
#include <QHash>

class InternalPageManager : public QObject
{
    Q_OBJECT

public:
    static InternalPageManager &instance();

    // Check if URL is an internal page (illuminate:// or newtab://)
    Q_INVOKABLE static bool isInternal(const QString &url);

    // Resolve an internal name or scheme to standard illuminate:// URL
    static QUrl resolve(const QString &input);

    // Get QML resource component path for internal page
    Q_INVOKABLE static QString qmlSource(const QString &url);
};
