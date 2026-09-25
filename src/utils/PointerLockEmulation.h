#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

class PointerLockEmulation : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(PointerLockEmu)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
    explicit PointerLockEmulation(QObject *parent = nullptr);
    ~PointerLockEmulation() override;

    bool active() const;

    Q_INVOKABLE bool begin();
    Q_INVOKABLE void end();

signals:
    void activeChanged(bool active);
    void movementReady(double dx, double dy);

private:
    Q_DISABLE_COPY(PointerLockEmulation)
    void setActiveLocal(bool on);

    class Private;
    Private *d;
};