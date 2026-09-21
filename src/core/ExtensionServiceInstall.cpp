#include "ExtensionService.h"
#include "../utils/BrowserLogger.h"
#include "../utils/WebVersion.h"
#include "ExtensionServiceInternals.h"

#include <QDir>
#include <QFile>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QProcess>
#include <QSysInfo>
#include <QTemporaryFile>
#include <QTimer>
#include <QUrl>
#include <QtEndian>
#include <QtGlobal>

#include <QWebEngineExtensionManager>

#include <functional>
#include <memory>
#include <optional>

// well this was hell to figure out

namespace
{
    // strip CRX header from a QByteArray containing CRX file data.
    // returns raw ZIP data if successful, empty QByteArray on failure.
    //
    //   CRX2: "Cr24" | version=2 | publicKeyLen | signatureLen | publicKey | signature | zip
    //   CRX3: "Cr24" | version=3 | headerLen     | protobuf header (headerLen bytes)    | zip
    QByteArray stripCrxHeader(const QByteArray &crx)
    {
        constexpr int kMinPrefix = 12; // magic + version + first length field

        if (crx.size() < kMinPrefix)
        {
            BrowserLogger::instance().warning("ExtensionService", "CRX data too short for header");
            return {};
        }

        if (!crx.startsWith("Cr24"))
        {
            BrowserLogger::instance().warning("ExtensionService", "Invalid CRX magic number");
            return {};
        }

        // unaligned-safe little-endian reads.
        const auto readU32 = [&crx](int offset) -> quint32
        {
            return qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(crx.constData()) + offset);
        };

        const quint32 version = readU32(4);
        qint64 headerSize = 0;

        switch (version)
        {
        case 2:
            if (crx.size() < 16)
            {
                BrowserLogger::instance().warning("ExtensionService", "CRX2 data too short for header");
                return {};
            }
            headerSize = 16 + qint64(readU32(8)) + qint64(readU32(12));
            break;
        case 3:
            headerSize = 12 + qint64(readU32(8));
            break;
        default:
            BrowserLogger::instance().warning("ExtensionService", QString("Unsupported CRX version: %1").arg(version));
            return {};
        }

        if (headerSize >= crx.size())
        {
            BrowserLogger::instance().warning("ExtensionService", "CRX data too short to contain header and payload");
            return {};
        }

        const QByteArray payload = crx.mid(int(headerSize));

        // what follows header must be a zip
        // am i going crazy?
        if (!payload.startsWith("PK"))
        {
            BrowserLogger::instance().warning("ExtensionService", "CRX payload is not a zip archive");
            return {};
        }

        return payload;
    }

    QString joinPath(const QString &base, const QString &rel)
    {
        return rel.isEmpty() ? base : base + QStringLiteral("/") + rel;
    }

    QString crxOs()
    {
#if defined(Q_OS_WIN)
        return QStringLiteral("win");
#elif defined(Q_OS_MACOS)
        return QStringLiteral("mac");
#else
        return QStringLiteral("linux");
#endif
    }

    QString crxArch()
    {
        const QString a = QSysInfo::currentCpuArchitecture(); // "x86_64", "arm64", ...
        return a == QLatin1String("x86_64") ? QStringLiteral("x64") : a;
    }

    // mimic chrome request
    QUrl crxUpdateUrl(const QString &extensionId, const QString &version)
    {
        // x= carries its own key/value pairs, so it is encoded as a single value.
        const QString xValue = QStringLiteral("id=") + extensionId
                               + QStringLiteral("&installsource=ondemand&uc");

        const QString url =
            QStringLiteral("https://clients2.google.com/service/update2/crx"
                           "?response=redirect")
            + QStringLiteral("&os=") + crxOs()
            + QStringLiteral("&arch=") + crxArch()
            + QStringLiteral("&os_arch=") + QSysInfo::currentCpuArchitecture()
            + QStringLiteral("&prod=chromiumcrx&prodchannel=unknown")
            + QStringLiteral("&prodversion=") + version
            + QStringLiteral("&lang=en-US&acceptformat=crx2,crx3")
            + QStringLiteral("&x=") + QString::fromLatin1(QUrl::toPercentEncoding(xValue));

        return QUrl::fromEncoded(url.toUtf8());
    }
} // namespace

void ExtensionService::setDownloading(bool downloading)
{
    if (m_downloading == downloading)
        return;
    m_downloading = downloading;
    emit downloadingChanged();
}

void ExtensionService::setDownloadStatus(const QString &status)
{
    if (m_downloadStatus == status)
        return;
    m_downloadStatus = status;
    emit downloadStatusChanged();
}

void ExtensionService::finishInstall(bool ok, const QString &status)
{
    BrowserLogger::instance().debug("ExtensionService",
                                    QStringLiteral("finishInstall ok=%1 status='%2'").arg(ok ? "true" : "false").arg(status));
    if (!ok)
        BrowserLogger::instance().warning("ExtensionService", status);
    setDownloading(false);
    setDownloadStatus(status);
}

void ExtensionService::installFromCrxUrl(const QString &extensionId, const QString &name, const QString &prodVersion)
{
    BrowserLogger::instance().debug("ExtensionService",
                                    QStringLiteral("installFromCrxUrl requested id=%1 name='%2' prodVersion=%3 downloading=%4")
                                        .arg(extensionId, name, prodVersion, m_downloading ? "true" : "false"));

    if (m_downloading)
    {
        BrowserLogger::instance().warning("ExtensionService", "installFromCrxUrl: already downloading, request ignored");
        return;
    }

    if (!ext::isValidId(extensionId))
    {
        BrowserLogger::instance().warning("ExtensionService", "installFromCrxUrl: invalid extension id " + extensionId);
        setDownloadStatus(QStringLiteral("Invalid extension id: ") + extensionId);
        return;
    }

    // default to our chrome version
    const QString version = prodVersion.isEmpty() ? chromiumVersion() : prodVersion;

    const QUrl qurl = crxUpdateUrl(extensionId, version);
    const QString crxUrl = qurl.toString(QUrl::FullyEncoded); // for logging
    BrowserLogger::instance().debug("ExtensionService", "installFromCrxUrl: CRX url=" + crxUrl);

    if (!qurl.isValid() || (qurl.scheme() != QLatin1String("http") && qurl.scheme() != QLatin1String("https")))
    {
        BrowserLogger::instance().warning("ExtensionService", "installFromCrxUrl: invalid download URL " + crxUrl);
        setDownloadStatus(QStringLiteral("Invalid download URL for CRX"));
        return;
    }

    // fallback to ID for name
    const QString displayName = name.isEmpty() ? extensionId : name;

    setDownloading(true);
    setDownloadStatus(QStringLiteral("Downloading ") + displayName + QStringLiteral("…"));

    QNetworkRequest req{qurl};
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setRawHeader("User-Agent", chromeUserAgent().toUtf8());
    req.setRawHeader("Accept", "*/*");
    req.setTransferTimeout(60000);

    QNetworkReply *reply = m_nam->get(req);
    BrowserLogger::instance().debug("ExtensionService",
                                    QStringLiteral("installFromCrxUrl: GET issued for %1").arg(crxUrl));

    connect(reply, &QNetworkReply::finished, this, [this, reply, extensionId, name, displayName]()
    {
        reply->deleteLater();

        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        BrowserLogger::instance().debug("ExtensionService",
            QStringLiteral("installFromCrxUrl: HTTP %1 for %2").arg(httpStatus).arg(extensionId));

        if (reply->error() != QNetworkReply::NoError) {
            BrowserLogger::instance().warning("ExtensionService",
                QStringLiteral("installFromCrxUrl: network error for %1: %2").arg(extensionId, reply->errorString()));
            finishInstall(false, QStringLiteral("Download failed: ") + reply->errorString());
            return;
        }

        // ah errors
        if (httpStatus == 204) {
            BrowserLogger::instance().warning("ExtensionService",
                QStringLiteral("installFromCrxUrl: HTTP 204 for %1, nothing to download").arg(extensionId));
            finishInstall(false, QStringLiteral("Not available for this browser version or package format (HTTP 204)"));
            return;
        }
        if (httpStatus != 200) {
            BrowserLogger::instance().warning("ExtensionService",
                QStringLiteral("installFromCrxUrl: unexpected HTTP %1 for %2").arg(httpStatus).arg(extensionId));
            finishInstall(false, QStringLiteral("Download failed: HTTP %1").arg(httpStatus));
            return;
        }

        QByteArray data = reply->readAll();
        BrowserLogger::instance().debug("ExtensionService",
            QStringLiteral("installFromCrxUrl: got %1 bytes (raw) for %2").arg(data.size()).arg(extensionId));
        if (data.isEmpty()) {
            BrowserLogger::instance().warning("ExtensionService", "installFromCrxUrl: empty response");
            finishInstall(false, QStringLiteral("Download failed: empty response"));
            return;
        }

        setDownloadStatus(QStringLiteral("Extracting ") + displayName + QStringLiteral("…"));

        // strip crx header
        const int rawSize = data.size();
        data = stripCrxHeader(data);
        BrowserLogger::instance().debug("ExtensionService",
            QStringLiteral("installFromCrxUrl: stripped CRX header %1 -> %2 bytes").arg(rawSize).arg(data.size()));
        if (data.isEmpty()) {
            BrowserLogger::instance().warning("ExtensionService",
                QStringLiteral("installFromCrxUrl: header strip failed or invalid CRX for %1").arg(extensionId));
            finishInstall(false, QStringLiteral("Failed to strip CRX header or invalid CRX file"));
            return;
        }

        // extract into staging dict
        const QString stagingDir = stagingRoot() + QStringLiteral("/") + extensionId;
        QDir(stagingDir).removeRecursively();
        if (!QDir().mkpath(stagingDir)) {
            BrowserLogger::instance().warning("ExtensionService", "installFromCrxUrl: cannot create staging dir " + stagingDir);
            finishInstall(false, QStringLiteral("Failed to create staging directory"));
            return;
        }
        BrowserLogger::instance().debug("ExtensionService", "installFromCrxUrl: extracting to " + stagingDir);

        extractZipAsync(data, stagingDir, [this, extensionId, name, stagingDir](bool ok) {
            BrowserLogger::instance().debug("ExtensionService",
                QStringLiteral("installFromCrxUrl: extract finished ok=%1 for %2").arg(ok ? "true" : "false").arg(extensionId));
            if (!ok) {
                QDir(stagingDir).removeRecursively();
                finishInstall(false, QStringLiteral("Failed to extract extension archive"));
                return;
            }
            completeInstall(extensionId, name, stagingDir);
        });
    });
}

void ExtensionService::completeInstall(const QString &id, const QString &fallbackName, const QString &stagingDir)
{
    auto fail = [this, &stagingDir](const QString &message)
    {
        QDir(stagingDir).removeRecursively();
        finishInstall(false, message);
    };

    // manifest needs to be at top 
    QString relDir;
    if (!locateManifestDir(stagingDir, &relDir))
    {
        fail(QStringLiteral("No manifest.json found in the archive"));
        return;
    }

    ManifestInfo mi;
    mi.name = fallbackName;
    if (!parseManifest(joinPath(stagingDir, relDir), mi))
    {
        fail(QStringLiteral("manifest.json is missing or invalid"));
        return;
    }

    // only MV3 is supported
    if (mi.manifestVersion != 3)
    {
        fail(QStringLiteral("%1 uses Manifest V%2. Qt WebEngine only supports Manifest V3 extensions.")
                 .arg(mi.name, QString::number(mi.manifestVersion)));
        return;
    }

    const QString rootDir = rootDirFor(id);
    if (rootDir.isEmpty())
    {
        fail(QStringLiteral("Invalid extension id"));
        return;
    }
    const QString finalManifestDir = joinPath(rootDir, relDir);

    // remember what is installed
    const int existingRow = indexOfId(id);
    std::optional<QWebEngineExtensionInfo> oldInfo;
    QString oldNormalized;
    if (existingRow >= 0)
    {
        oldInfo = findEngineInfo(m_extensions.at(existingRow));
        oldNormalized = ext::normalizedPath(m_extensions.at(existingRow).path);
    }

    // swap staging -> final, keeping the old copy until the swap succeeded.
    const QString backupDir = stagingRoot() + QStringLiteral("/") + id + QStringLiteral(".old");
    bool hadOld = false;
    if (QDir(rootDir).exists())
    {
        QDir(backupDir).removeRecursively();
        if (!QDir().rename(rootDir, backupDir))
        {
            fail(QStringLiteral("Could not replace the existing installation (files in use?)"));
            return;
        }
        hadOld = true;
    }
    if (!QDir().rename(stagingDir, rootDir))
    {
        if (hadOld)
            QDir().rename(backupDir, rootDir);
        fail(QStringLiteral("Failed to move the extension into place"));
        return;
    }
    if (hadOld)
        QDir(backupDir).removeRecursively();

    // update the model
    ExtensionItem item;
    if (existingRow >= 0)
        item = m_extensions.at(existingRow);
    item.id = id;
    item.name = mi.name;
    item.version = mi.version;
    item.description = mi.description;
    item.author = mi.author;
    item.homepageUrl = mi.homepageUrl;
    item.permissions = mi.permissions;
    item.hostPermissions = mi.hostPermissions;
    item.hasUserScripts = mi.hasUserScripts;
    item.sizeBytes = ext::dirSizeBytes(rootDir);
    item.path = finalManifestDir;
    item.iconPath = mi.iconRel.isEmpty() ? QString() : joinPath(finalManifestDir, mi.iconRel);
    item.popupPath = mi.popupRel.isEmpty() ? QString() : joinPath(finalManifestDir, mi.popupRel);
    item.enabled = true;

    if (existingRow >= 0)
    {
        m_extensions[existingRow] = item;
        emit dataChanged(index(existingRow), index(existingRow));
    }
    else
    {
        beginInsertRows(QModelIndex(), int(m_extensions.size()), int(m_extensions.size()));
        m_extensions.append(item);
        endInsertRows();
        emit countChanged();
    }
    saveToDisk();

    // load into web engine
    if (auto *mgr = ensureManager())
    {
        if (oldInfo && oldNormalized != ext::normalizedPath(finalManifestDir))
            mgr->unloadExtension(*oldInfo);   // manifest sub-directory changed between versions
        mgr->loadExtension(finalManifestDir); // same path => reloads
    }
    else
    {
        BrowserLogger::instance().warning("ExtensionService", QStringLiteral("No extension manager yet; %1 will be loaded by installToWebEngine()").arg(mi.name));
    }

    finishInstall(true, QStringLiteral("Installed ") + mi.name);
}

// unzip.
void ExtensionService::extractZipAsync(const QByteArray &zipData, const QString &destDir,
                                       std::function<void(bool)> done)
{
    auto tmp = std::make_shared<QTemporaryFile>(QDir::tempPath() + QStringLiteral("/extension-XXXXXX.zip"));
    if (!tmp->open() || tmp->write(zipData) != zipData.size())
    {
        BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Could not write temporary archive"));
        done(false);
        return;
    }
    tmp->close(); // keeps the file on disk until `tmp` is destroyed
    const QString tmpPath = tmp->fileName();

    auto *proc = new QProcess(this);

    connect(proc, &QProcess::finished, this,
            [proc, tmp, done](int exitCode, QProcess::ExitStatus status)
            {
#if defined(Q_OS_WIN)
                const bool ok = status == QProcess::NormalExit && exitCode == 0;
#else
                // unzip exits with 1 for non-fatal warnings.
                const bool ok = status == QProcess::NormalExit && (exitCode == 0 || exitCode == 1);
#endif
                if (!ok)
                {
                    BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Archive extraction failed (exit=%1): %2")
                                                                              .arg(exitCode)
                                                                              .arg(QString::fromLocal8Bit(proc->readAllStandardError())));
                }
                proc->deleteLater();
                done(ok);
            });

    connect(proc, &QProcess::errorOccurred, this,
            [proc, done](QProcess::ProcessError error)
            {
                if (error != QProcess::FailedToStart)
                    return; // Crashed etc. is reported through finished()
                BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Could not start the archive extraction tool"));
                proc->deleteLater();
                done(false);
            });

    // Safety net against a hung extraction.
    QTimer::singleShot(60000, proc, [proc]()
                       {
        if (proc->state() != QProcess::NotRunning)
            proc->kill(); });

#if defined(Q_OS_WIN)
    // Prefer the system bsdtar: a GNU tar earlier in PATH (e.g. from Git for Windows) can't read zip files.
    const QString sysTar = qEnvironmentVariable("SystemRoot", QStringLiteral("C:\\Windows"))
                           + QStringLiteral("\\System32\\tar.exe");
    proc->start(QFile::exists(sysTar) ? sysTar : QStringLiteral("tar"),
                {QStringLiteral("-xf"), tmpPath, QStringLiteral("-C"), destDir});
#else
    proc->start(QStringLiteral("unzip"), {QStringLiteral("-q"), QStringLiteral("-o"), tmpPath,
                                          QStringLiteral("-d"), destDir});
#endif
}