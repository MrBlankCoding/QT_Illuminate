#include "ExtensionService.h"
#include "../utils/BrowserLogger.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QTemporaryFile>

#include <QQuickWebEngineProfile>
#include <QWebEngineExtensionManager>

ExtensionService::ExtensionService(QObject *parent)
    : QAbstractListModel(parent)
    , m_nam(new QNetworkAccessManager(this))
{
    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    m_baseDir = dataDir + QStringLiteral("/extensions");
    QDir().mkpath(m_baseDir);

    loadFromDisk();
    BrowserLogger::instance().info("ExtensionService",
        QString("Initialized with baseDir=%1, extensions count=%2").arg(m_baseDir, QString::number(m_extensions.size())));
}

int ExtensionService::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_extensions.size();
}

QVariant ExtensionService::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_extensions.size())
        return {};

    const ExtensionItem &item = m_extensions.at(index.row());
    switch (role) {
    case IdRole:          return item.id;
    case NameRole:        return item.name;
    case VersionRole:     return item.version;
    case DescriptionRole: return item.description;
    case PathRole:        return item.path;
    case IconPathRole:    return item.iconPath;
    case PopupPathRole:   return item.popupPath;
    case EnabledRole:     return item.enabled;
    case PinnedRole:      return item.pinned;
    default:              return {};
    }
}

QHash<int, QByteArray> ExtensionService::roleNames() const
{
    return {
        { IdRole,          "id" },
        { NameRole,        "name" },
        { VersionRole,     "version" },
        { DescriptionRole, "description" },
        { PathRole,        "path" },
        { IconPathRole,    "iconPath" },
        { PopupPathRole,   "popupPath" },
        { EnabledRole,     "enabled" },
        { PinnedRole,      "pinned" }
    };
}

bool ExtensionService::isInstalled(const QString &id) const
{
    for (const auto &item : m_extensions) {
        if (item.id == id) return true;
    }
    return false;
}

QString ExtensionService::getPopupUrl(const QString &id) const
{
    const ExtensionItem *foundItem = nullptr;
    for (const auto &item : m_extensions) {
        if (item.id == id && item.enabled) {
            foundItem = &item;
            break;
        }
    }
    if (!foundItem) return {};

    auto *profile = QQuickWebEngineProfile::defaultProfile();
    if (profile && profile->extensionManager()) {
        auto *mgr = profile->extensionManager();
        for (const auto &ext : mgr->extensions()) {
            if (ext.path() == foundItem->path || ext.name() == foundItem->name) {
                if (ext.actionPopupUrl().isValid() && !ext.actionPopupUrl().isEmpty()) {
                    BrowserLogger::instance().info("ExtensionService", QString("getPopupUrl %1 -> %2").arg(id, ext.actionPopupUrl().toString()));
                    return ext.actionPopupUrl().toString();
                }
                if (!ext.id().isEmpty() && !foundItem->popupPath.isEmpty()) {
                    QString rel = QDir(foundItem->path).relativeFilePath(foundItem->popupPath);
                    QString res = QStringLiteral("chrome-extension://%1/%2").arg(ext.id(), rel);
                    BrowserLogger::instance().info("ExtensionService", QString("getPopupUrl %1 -> %2").arg(id, res));
                    return res;
                }
            }
        }
    }

    if (!foundItem->popupPath.isEmpty()) {
        return QUrl::fromLocalFile(foundItem->popupPath).toString();
    }
    return {};
}

QString ExtensionService::getInstalledIconPath(const QString &id) const
{
    for (const auto &item : m_extensions) {
        if (item.id == id && !item.iconPath.isEmpty()) {
            return item.iconPath;
        }
    }
    return {};
}

void ExtensionService::togglePin(const QString &id)
{
    for (int i = 0; i < m_extensions.size(); ++i) {
        if (m_extensions[i].id == id) {
            m_extensions[i].pinned = !m_extensions[i].pinned;
            emit dataChanged(index(i), index(i), { PinnedRole });
            saveToDisk();
            break;
        }
    }
}

void ExtensionService::toggleExtension(const QString &id)
{
    for (int i = 0; i < m_extensions.size(); ++i) {
        if (m_extensions[i].id == id) {
            m_extensions[i].enabled = !m_extensions[i].enabled;
            emit dataChanged(index(i), index(i), { EnabledRole });
            saveToDisk();

            auto *profile = QQuickWebEngineProfile::defaultProfile();
            if (profile && profile->extensionManager()) {
                auto *mgr = profile->extensionManager();
                for (const auto &ext : mgr->extensions()) {
                    if (ext.path() == m_extensions[i].path || ext.name() == m_extensions[i].name) {
                        mgr->setExtensionEnabled(ext, m_extensions[i].enabled);
                        break;
                    }
                }
            }
            break;
        }
    }
}

void ExtensionService::uninstallExtension(const QString &id)
{
    int foundIdx = -1;
    for (int i = 0; i < m_extensions.size(); ++i) {
        if (m_extensions[i].id == id) {
            foundIdx = i;
            break;
        }
    }
    if (foundIdx < 0) return;

    const ExtensionItem item = m_extensions.at(foundIdx);

    auto *profile = QQuickWebEngineProfile::defaultProfile();
    if (profile && profile->extensionManager()) {
        auto *mgr = profile->extensionManager();
        for (const auto &ext : mgr->extensions()) {
            if (ext.path() == item.path || ext.name() == item.name) {
                mgr->uninstallExtension(ext);
                break;
            }
        }
    }

    // Remove folder on disk
    QDir(item.path).removeRecursively();

    beginRemoveRows(QModelIndex(), foundIdx, foundIdx);
    m_extensions.removeAt(foundIdx);
    endRemoveRows();
    emit countChanged();
    emit extensionUninstalled(id);
    saveToDisk();
}

void ExtensionService::installToWebEngine()
{
    auto *profile = QQuickWebEngineProfile::defaultProfile();
    if (!profile) return;
    auto *mgr = profile->extensionManager();
    if (!mgr) return;

    if (!m_signalsConnected) {
        m_signalsConnected = true;
        connect(mgr, &QWebEngineExtensionManager::installFinished, this, [this, mgr](const QWebEngineExtensionInfo &ext) {
            BrowserLogger::instance().info("ExtensionService",
                QString("installFinished: name=%1 id=%2 installed=%3 loaded=%4 popup=%5 error=%6")
                    .arg(ext.name(), ext.id(), QString::number(ext.isInstalled()),
                         QString::number(ext.isLoaded()), ext.actionPopupUrl().toString(), ext.error()));
            if (ext.isInstalled() || ext.isLoaded()) {
                for (const auto &item : m_extensions) {
                    if (item.enabled && (ext.path() == item.path || ext.name() == item.name))
                        break;
                }
            }
        });
        connect(mgr, &QWebEngineExtensionManager::loadFinished, this, [this, mgr](const QWebEngineExtensionInfo &ext) {
            BrowserLogger::instance().info("ExtensionService",
                QString("loadFinished: name=%1 id=%2 installed=%3 loaded=%4 popup=%5 error=%6")
                    .arg(ext.name(), ext.id(), QString::number(ext.isInstalled()),
                         QString::number(ext.isLoaded()), ext.actionPopupUrl().toString(), ext.error()));
            if (ext.isLoaded()) {
                for (const auto &item : m_extensions) {
                    if (item.enabled && (ext.path() == item.path || ext.name() == item.name))
                        break;
                }
            }
        });
    }

    BrowserLogger::instance().info("ExtensionService", QString("ExtensionManager installPath=%1").arg(mgr->installPath()));
    QDir().mkpath(mgr->installPath());

    // Enable existing extensions that were persisted by WebEngine profile
    for (const auto &ext : mgr->extensions()) {
        for (const auto &item : m_extensions) {
            if (item.enabled && (ext.path() == item.path || ext.name() == item.name)) {
                if (!ext.isEnabled()) {
                    mgr->setExtensionEnabled(ext, true);
                }
                break;
            }
        }
    }

    // Install any extension not yet known to manager
    for (const auto &item : m_extensions) {
        if (!item.enabled || !QDir(item.path).exists()) continue;

        bool found = false;
        for (const auto &ext : mgr->extensions()) {
            if (ext.path() == item.path || ext.name() == item.name) {
                found = true;
                break;
            }
        }
        if (!found) {
            BrowserLogger::instance().info("ExtensionService", QString("Loading extension %1 from %2").arg(item.name, item.path));
            mgr->loadExtension(item.path);
        }
    }
}

void ExtensionService::installFromZipUrl(const QString &id, const QString &name, const QString &url)
{
    if (m_downloading) return;

    m_downloading = true;
    m_downloadStatus = QStringLiteral("Downloading ") + name + QStringLiteral("…");
    emit downloadingChanged();
    emit downloadStatusChanged();

    QNetworkRequest req{QUrl(url)};
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setRawHeader("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)");

    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, id, name]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            m_downloading = false;
            m_downloadStatus = QStringLiteral("Download failed: ") + reply->errorString();
            emit downloadingChanged();
            emit downloadStatusChanged();
            return;
        }

        const QByteArray data = reply->readAll();
        m_downloadStatus = QStringLiteral("Extracting ") + name + QStringLiteral("…");
        emit downloadStatusChanged();

        const QString targetDir = m_baseDir + QStringLiteral("/") + id;
        QDir(targetDir).removeRecursively();
        QDir().mkpath(targetDir);

        if (!extractZip(data, targetDir)) {
            m_downloading = false;
            m_downloadStatus = QStringLiteral("Failed to extract extension archive");
            emit downloadingChanged();
            emit downloadStatusChanged();
            return;
        }

        // Detect if manifest is in a subdirectory (e.g. uBlock0.chromium/manifest.json)
        QString manifestDir = targetDir;
        if (!QFile::exists(manifestDir + QStringLiteral("/manifest.json"))) {
            QDir d(targetDir);
            const QStringList subdirs = d.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
            for (const QString &sub : subdirs) {
                if (QFile::exists(targetDir + QStringLiteral("/") + sub + QStringLiteral("/manifest.json"))) {
                    manifestDir = targetDir + QStringLiteral("/") + sub;
                    break;
                }
            }
        }

        QString extName = name;
        QString version = QStringLiteral("1.0");
        QString description;
        QString iconPath;
        QString popupPath;
        parseManifest(manifestDir, extName, version, description, iconPath, popupPath);

        // Remove old entry if existed
        for (int i = 0; i < m_extensions.size(); ++i) {
            if (m_extensions[i].id == id) {
                beginRemoveRows(QModelIndex(), i, i);
                m_extensions.removeAt(i);
                endRemoveRows();
                break;
            }
        }

        ExtensionItem item;
        item.id = id;
        item.name = extName;
        item.version = version;
        item.description = description;
        item.path = manifestDir;
        item.iconPath = iconPath;
        item.popupPath = popupPath;
        item.enabled = true;

        beginInsertRows(QModelIndex(), m_extensions.size(), m_extensions.size());
        m_extensions.append(item);
        endInsertRows();
        emit countChanged();
        saveToDisk();

        auto *profile = QQuickWebEngineProfile::defaultProfile();
        if (profile && profile->extensionManager()) {
            profile->extensionManager()->loadExtension(manifestDir);
        }

        m_downloading = false;
        m_downloadStatus = QStringLiteral("Installed ") + extName;
        emit downloadingChanged();
        emit downloadStatusChanged();
        emit extensionInstalled(id);
    });
}

bool ExtensionService::extractZip(const QByteArray &zipData, const QString &destDir)
{
    QTemporaryFile tmpFile;
    if (!tmpFile.open()) return false;
    tmpFile.write(zipData);
    tmpFile.flush();
    const QString tmpPath = tmpFile.fileName();

#if defined(Q_OS_WIN)
    QProcess proc;
    proc.start(QStringLiteral("tar"), {QStringLiteral("-xf"), tmpPath, QStringLiteral("-C"), destDir});
    return proc.waitForFinished(30000) && proc.exitCode() == 0;
#else
    QProcess proc;
    proc.start(QStringLiteral("unzip"), {QStringLiteral("-q"), QStringLiteral("-o"), tmpPath, QStringLiteral("-d"), destDir});
    return proc.waitForFinished(30000) && proc.exitCode() == 0;
#endif
}

bool ExtensionService::parseManifest(const QString &dirPath, QString &name, QString &version, QString &description, QString &iconPath, QString &popupPath)
{
    QFile f(dirPath + QStringLiteral("/manifest.json"));
    if (!f.open(QIODevice::ReadOnly)) return false;

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject()) return false;

    const QJsonObject obj = doc.object();

    auto resolveMsg = [&](const QString &str) -> QString {
        if (!str.startsWith(QLatin1String("__MSG_")) || !str.endsWith(QLatin1String("__")))
            return str;
        const QString key = str.mid(6, str.length() - 8);
        QString locale = obj.value(QStringLiteral("default_locale")).toString();
        if (locale.isEmpty()) locale = QStringLiteral("en");
        QFile mf(dirPath + QStringLiteral("/_locales/") + locale + QStringLiteral("/messages.json"));
        if (mf.open(QIODevice::ReadOnly)) {
            const QJsonObject mObj = QJsonDocument::fromJson(mf.readAll()).object();
            if (mObj.contains(key)) {
                return mObj.value(key).toObject().value(QStringLiteral("message")).toString();
            }
        }
        return str;
    };

    if (obj.contains(QStringLiteral("name"))) {
        name = resolveMsg(obj.value(QStringLiteral("name")).toString());
    }
    if (obj.contains(QStringLiteral("version"))) {
        version = obj.value(QStringLiteral("version")).toString();
    }
    if (obj.contains(QStringLiteral("description"))) {
        description = resolveMsg(obj.value(QStringLiteral("description")).toString());
    }

    // Parse action / browser_action for popup and icon
    QJsonObject actionObj;
    if (obj.contains(QStringLiteral("action")) && obj.value(QStringLiteral("action")).isObject()) {
        actionObj = obj.value(QStringLiteral("action")).toObject();
    } else if (obj.contains(QStringLiteral("browser_action")) && obj.value(QStringLiteral("browser_action")).isObject()) {
        actionObj = obj.value(QStringLiteral("browser_action")).toObject();
    }

    if (!actionObj.isEmpty()) {
        if (actionObj.contains(QStringLiteral("default_popup"))) {
            QString p = actionObj.value(QStringLiteral("default_popup")).toString();
            if (!p.isEmpty()) popupPath = dirPath + QStringLiteral("/") + p;
        }
        if (actionObj.contains(QStringLiteral("default_icon"))) {
            QJsonValue iconVal = actionObj.value(QStringLiteral("default_icon"));
            if (iconVal.isObject()) {
                QJsonObject iconMap = iconVal.toObject();
                QString ic = iconMap.value(QStringLiteral("32")).toString();
                if (ic.isEmpty()) ic = iconMap.value(QStringLiteral("16")).toString();
                if (ic.isEmpty()) ic = iconMap.value(QStringLiteral("48")).toString();
                if (ic.isEmpty() && !iconMap.isEmpty()) ic = iconMap.begin().value().toString();
                if (!ic.isEmpty()) iconPath = dirPath + QStringLiteral("/") + ic;
            } else if (iconVal.isString()) {
                iconPath = dirPath + QStringLiteral("/") + iconVal.toString();
            }
        }
    }

    // Fallback to top-level "icons"
    if (iconPath.isEmpty() && obj.contains(QStringLiteral("icons")) && obj.value(QStringLiteral("icons")).isObject()) {
        QJsonObject icons = obj.value(QStringLiteral("icons")).toObject();
        QString ic = icons.value(QStringLiteral("32")).toString();
        if (ic.isEmpty()) ic = icons.value(QStringLiteral("48")).toString();
        if (ic.isEmpty()) ic = icons.value(QStringLiteral("128")).toString();
        if (ic.isEmpty()) ic = icons.value(QStringLiteral("16")).toString();
        if (!ic.isEmpty()) iconPath = dirPath + QStringLiteral("/") + ic;
    }

    return true;
}

void ExtensionService::loadFromDisk()
{
    QFile f(m_baseDir + QStringLiteral("/extensions.json"));
    if (!f.open(QIODevice::ReadOnly)) return;

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isArray()) return;

    m_extensions.clear();
    const QJsonArray arr = doc.array();
    for (const QJsonValue &v : arr) {
        if (!v.isObject()) continue;
        const QJsonObject o = v.toObject();
        ExtensionItem item;
        item.id = o.value(QStringLiteral("id")).toString();
        item.name = o.value(QStringLiteral("name")).toString();
        item.version = o.value(QStringLiteral("version")).toString();
        item.description = o.value(QStringLiteral("description")).toString();
        item.path = o.value(QStringLiteral("path")).toString();
        item.iconPath = o.value(QStringLiteral("iconPath")).toString();
        item.popupPath = o.value(QStringLiteral("popupPath")).toString();
        item.enabled = o.value(QStringLiteral("enabled")).toBool(true);
        item.pinned  = o.value(QStringLiteral("pinned")).toBool(true);
        if (QDir(item.path).exists()) {
            m_extensions.append(item);
        }
    }
}

void ExtensionService::saveToDisk()
{
    QJsonArray arr;
    for (const auto &item : m_extensions) {
        QJsonObject o;
        o[QStringLiteral("id")] = item.id;
        o[QStringLiteral("name")] = item.name;
        o[QStringLiteral("version")] = item.version;
        o[QStringLiteral("description")] = item.description;
        o[QStringLiteral("path")] = item.path;
        o[QStringLiteral("iconPath")] = item.iconPath;
        o[QStringLiteral("popupPath")] = item.popupPath;
        o[QStringLiteral("enabled")] = item.enabled;
        o[QStringLiteral("pinned")]  = item.pinned;
        arr.append(o);
    }
    QFile f(m_baseDir + QStringLiteral("/extensions.json"));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(arr).toJson());
    }
}
