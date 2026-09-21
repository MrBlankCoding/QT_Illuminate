#pragma once

#include <QObject>
#include <QString>
#include "BrowserLogger.h"

//   logger.debug("TabBar",     "Tab activated: " + index)
//   logger.info ("Navigation", "Navigating to " + url)
//   logger.warning ("WebView",    "Load failed for " + url)
//   logger.error("Crash",      "Unexpected null model")

class LogBridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString logFilePath READ logFilePath CONSTANT)

public:
    explicit LogBridge(QObject *parent = nullptr) : QObject(parent) {}

    QString logFilePath() const { return BrowserLogger::instance().logFilePath(); }

    Q_INVOKABLE void debug(const QString &category, const QString &message)
    {
        BrowserLogger::instance().debug(category, message);
    }

    Q_INVOKABLE void info(const QString &category, const QString &message)
    {
        BrowserLogger::instance().info(category, message);
    }

     Q_INVOKABLE void warning(const QString &category, const QString &message)
    {
        BrowserLogger::instance().warning(category, message);
    }

    Q_INVOKABLE void error(const QString &category, const QString &message)
    {
        BrowserLogger::instance().error(category, message);
    }
};
