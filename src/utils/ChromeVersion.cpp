#include "ChromeVersion.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>

ChromeVersion::ChromeVersion(QObject *parent)
    : QObject(parent)
{
}

ChromeVersion &ChromeVersion::instance()
{
    static ChromeVersion singleton;
    return singleton;
}

QString ChromeVersion::cacheFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    return dir.isEmpty() ? QString() : dir + QStringLiteral("/chrome-version.txt");
}

void ChromeVersion::loadCache()
{
    const QString path = cacheFilePath();
    if (path.isEmpty())
        return;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QString cached = QString::fromUtf8(file.readAll()).trimmed();
    static const QRegularExpression kVersionPattern(QStringLiteral("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"));
    if (kVersionPattern.match(cached).hasMatch())
        m_latest = cached;
}

void ChromeVersion::saveCache(const QString &version) const
{
    const QString path = cacheFilePath();
    if (path.isEmpty())
        return;
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        file.write(version.toUtf8());
}

void ChromeVersion::start()
{
    if (m_started)
        return;
    m_started = true;

    loadCache();

    // skip the network when we already fetched today
    const QString path = cacheFilePath();
    if (!path.isEmpty())
    {
        const QDateTime written = QFileInfo(path).lastModified();
        if (written.isValid() && written.secsTo(QDateTime::currentDateTime()) < 24 * 60 * 60)
            return;
    }
    refresh();
}

void ChromeVersion::refresh()
{
    if (!m_nam)
        m_nam = new QNetworkAccessManager();
    QNetworkRequest request(QUrl(
        QStringLiteral("https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions.json")));
    request.setTransferTimeout(10000);
    QNetworkReply *reply = m_nam->get(request);
    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply] {
        onReplyFinished(reply);
    });
}

void ChromeVersion::onReplyFinished(QNetworkReply *reply)
{
    reply->deleteLater();
    if (reply->error() != QNetworkReply::NoError)
        return;
    const QJsonObject channels = QJsonDocument::fromJson(reply->readAll())
                                     .object()
                                     .value(QStringLiteral("channels"))
                                     .toObject();
    const QString version = channels.value(QStringLiteral("Stable"))
                                .toObject()
                                .value(QStringLiteral("version"))
                                .toString()
                                .trimmed();
    static const QRegularExpression kVersionPattern(QStringLiteral("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"));
    if (!kVersionPattern.match(version).hasMatch())
        return;
    if (version == m_latest)
        return;
    m_latest = version;
    saveCache(version);
}

QString ChromeVersion::latest() const
{
    return m_latest;
}