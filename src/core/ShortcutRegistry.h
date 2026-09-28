#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include "../utils/ExternalQmlSingleton.h"

class QSettings;

// Owns the app's keyboard shortcuts. Both the live Shortcut items and the
// settings UI read their sequences from here, so a binding can't drift out of
// sync with what the settings page shows.
class ShortcutRegistry : public QObject, public ExternalQmlSingleton<ShortcutRegistry>
{
    Q_DISABLE_COPY_MOVE(ShortcutRegistry)
    Q_OBJECT
    QML_NAMED_ELEMENT(Shortcuts)
    QML_SINGLETON

    // static catalog: [{id, label, category}], ordered by category
    Q_PROPERTY(QVariantList commands READ commands CONSTANT)
    // true once anything differs from its default; drives the "Reset all" button
    Q_PROPERTY(bool hasCustomizations READ hasCustomizations NOTIFY shortcutsChanged)

public:
    // no default: an ExternalQmlSingleton must not be default-constructible
    explicit ShortcutRegistry(QObject *parent);

    // [{id, label, category}]
    QVariantList commands() const;

    // the settings page's row title, and the id behind it
    Q_INVOKABLE QString labelFor(const QString &commandId) const;

    // the sequences bound to a command: the user's override, else the default
    Q_INVOKABLE QStringList sequences(const QString &commandId) const;

    // what to show in the settings UI, e.g. "⌘⇧C" on macOS
    Q_INVOKABLE QString displaySequence(const QString &commandId) const;

    Q_INVOKABLE bool isCustomized(const QString &commandId) const;
    bool hasCustomizations() const;

    // an empty sequence unbinds the command
    Q_INVOKABLE bool setSequence(const QString &commandId, const QString &sequence);
    Q_INVOKABLE void reset(const QString &commandId);
    Q_INVOKABLE void resetAll();

    // the command already bound to this sequence, or empty. ignores commandId
    // itself so rebinding a command to its current value isn't a conflict.
    Q_INVOKABLE QString commandUsing(const QString &sequence, const QString &exceptCommandId = QString()) const;

    // turns a QML KeyEvent (key + modifier mask) into a portable sequence.
    // empty when the combination is unusable as a binding.
    Q_INVOKABLE static QString sequenceFromKey(int key, int modifierMask);

signals:
    void shortcutsChanged();

private:
    struct Command
    {
        QString id;
        QString label;
        QString category;
        // the shipped combinations; the user's override replaces all of them
        QStringList defaults;
    };

    static const QList<Command> &table();
    static QList<Command> buildTable();
    static const Command *find(const QString &commandId);
    static QString normalize(const QString &sequence);

    QSettings *m_settings = nullptr;
};
