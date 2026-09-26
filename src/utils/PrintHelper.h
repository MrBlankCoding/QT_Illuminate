#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

class PrintHelper : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit PrintHelper(QObject *parent = nullptr);
    Q_INVOKABLE void printPdf(const QString &filePath);
};