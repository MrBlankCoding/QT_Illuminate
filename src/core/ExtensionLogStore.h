#pragma once

#include <QHash>
#include <QObject>
#include <QVariantList>

// Per-extension JS console capture (popup + tab pages live on illum-ext://host).
// Feeds the "more details" overlay on the installed-extensions page.
class ExtensionLogStore : public QObject
{
    Q_OBJECT
public:
    explicit ExtensionLogStore(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE void append(const QString &id, int level, const QString &message);
    Q_INVOKABLE QVariantList forExtension(const QString &id) const { return m_logs.value(id); }
    Q_INVOKABLE void clear(const QString &id);

signals:
    void changed(const QString &id);

private:
    QHash<QString, QVariantList> m_logs;
};