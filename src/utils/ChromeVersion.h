#pragma once

#include <QObject>
#include <QString>

class QNetworkAccessManager;
class QNetworkReply;
class ChromeVersion : public QObject
{
    Q_OBJECT

public:
    static ChromeVersion &instance();
    void start();
    QString latest() const;

private:
    explicit ChromeVersion(QObject *parent = nullptr);
    void loadCache();
    void saveCache(const QString &version) const;
    void refresh();
    void onReplyFinished(QNetworkReply *reply);
    static QString cacheFilePath();

    QString m_latest = QStringLiteral("154.0.8037.57");
    bool m_started = false;
    QNetworkAccessManager *m_nam = nullptr;
};