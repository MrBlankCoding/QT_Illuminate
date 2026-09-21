#include "ExtensionService.h"
#include "ExtensionSchemeHandler.h"
#include "../utils/BrowserLogger.h"
#include "ExtensionServiceInternals.h"

#include <QDir>
#include <QFile>
#include <QNetworkAccessManager>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <QQuickWebEngineProfile>
#include <QWebEngineExtensionManager>

#include <memory>

static bool isUsable(const std::optional<QWebEngineExtensionInfo> &info)
{
    return info && info->isLoaded() && !info->id().isEmpty();
}

ExtensionService::ExtensionService(QObject *parent)
    : QAbstractListModel(parent), m_nam(new QNetworkAccessManager(this))
{
    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    m_baseDir = dataDir + QStringLiteral("/extensions");
    QDir().mkpath(m_baseDir);

    // left overs from interupted install
    QDir(stagingRoot()).removeRecursively();

    loadFromDisk();
    BrowserLogger::instance().info("ExtensionService", QStringLiteral("Initialized with baseDir=%1, extensions count=%2")
                                                           .arg(m_baseDir, QString::number(m_extensions.size())));
}

int ExtensionService::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return int(m_extensions.size());
}

QVariant ExtensionService::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_extensions.size())
        return {};

    const ExtensionItem &item = m_extensions.at(index.row());
    switch (role)
    {
    case IdRole:
        return item.id;
    case NameRole:
        return item.name;
    case VersionRole:
        return item.version;
    case DescriptionRole:
        return item.description;
    case PathRole:
        return item.path;
    case IconPathRole:
        return item.iconPath;
    case PopupPathRole:
        return item.popupPath;
    case EnabledRole:
        return item.enabled;
    case PinnedRole:
        return item.pinned;
    case AuthorRole:
        return item.author;
    case HomepageRole:
        return item.homepageUrl;
    case PermissionsRole:
        return item.permissions;
    case HostPermissionsRole:
        return item.hostPermissions;
    case UserScriptsRole:
        return item.hasUserScripts;
    case SizeRole:
        return item.sizeBytes;
    case UserScriptsEnabledRole:
        return item.userScriptsEnabled;
    default:
        return {};
    }
}

QHash<int, QByteArray> ExtensionService::roleNames() const
{
    return {
        {IdRole, "id"},
        {NameRole, "name"},
        {VersionRole, "version"},
        {DescriptionRole, "description"},
        {PathRole, "path"},
        {IconPathRole, "iconPath"},
        {PopupPathRole, "popupPath"},
        {EnabledRole, "enabled"},
        {PinnedRole, "pinned"},
        {AuthorRole, "author"},
        {HomepageRole, "homepageUrl"},
        {PermissionsRole, "permissions"},
        {HostPermissionsRole, "hostPermissions"},
        {UserScriptsRole, "hasUserScripts"},
        {SizeRole, "sizeBytes"},
        {UserScriptsEnabledRole, "userScriptsEnabled"}};
}

QQuickWebEngineProfile *ExtensionService::profile() const
{
    return QQuickWebEngineProfile::defaultProfile();
}

QWebEngineExtensionManager *ExtensionService::extensionManager() const
{
    auto *p = profile();
    return p ? p->extensionManager() : nullptr;
}

QWebEngineExtensionManager *ExtensionService::ensureManager()
{
    auto *mgr = extensionManager();
    if (!mgr)
        return nullptr;

    if (m_connectedManager != mgr)
    {
        if (m_connectedManager)
            disconnect(m_connectedManager.data(), nullptr, this, nullptr);
        m_connectedManager = mgr;

        connect(mgr, &QWebEngineExtensionManager::loadFinished,
                this, &ExtensionService::onLoadFinished);
        connect(mgr, &QWebEngineExtensionManager::unloadFinished,
                this, &ExtensionService::onUnloadFinished);
        connect(mgr, &QWebEngineExtensionManager::installFinished, this,
                [](const QWebEngineExtensionInfo &ext)
                {
                    BrowserLogger::instance().info("ExtensionService", QStringLiteral("installFinished: name=%1 id=%2 installed=%3 error=%4")
                                                                           .arg(ext.name(), ext.id(), QString::number(ext.isInstalled()), ext.error()));
                });

        BrowserLogger::instance().info("ExtensionService", QStringLiteral("Connected to extension manager, installPath=%1").arg(mgr->installPath()));
    }
    return mgr;
}

int ExtensionService::indexOfId(const QString &id) const
{
    for (int i = 0; i < m_extensions.size(); ++i)
    {
        if (m_extensions.at(i).id == id)
            return i;
    }
    return -1;
}

int ExtensionService::indexOfPath(const QString &path) const
{
    const QString wanted = ext::normalizedPath(path);
    if (wanted.isEmpty())
        return -1;
    for (int i = 0; i < m_extensions.size(); ++i)
    {
        if (ext::normalizedPath(m_extensions.at(i).path) == wanted)
            return i;
    }
    return -1;
}

std::optional<QWebEngineExtensionInfo> ExtensionService::findEngineInfo(const ExtensionItem &item) const
{
    const auto *mgr = extensionManager();
    if (!mgr)
        return std::nullopt;

    const QString wanted = ext::normalizedPath(item.path);
    const auto exts = mgr->extensions();
    for (const auto &ext : exts)
    {
        if (ext::normalizedPath(ext.path()) == wanted)
            return ext;
    }
    return std::nullopt;
}

bool ExtensionService::isInstalled(const QString &id) const
{
    return indexOfId(id) >= 0;
}

QString ExtensionService::getInstalledIconPath(const QString &id) const
{
    const int row = indexOfId(id);
    return row >= 0 ? m_extensions.at(row).iconPath : QString();
}

QString ExtensionService::rewriteExtensionUrl(const QString &url)
{
    const QString name = QStringLiteral("chrome-extension:");
    if (!url.startsWith(name, Qt::CaseInsensitive))
        return url;
    return QStringLiteral("illum-ext:") + url.mid(name.size());
}

QString ExtensionService::buildPageUrl(const ExtensionItem &item, const QString &relativePath) const
{
    if (!item.enabled)
        return {};

    const auto info = findEngineInfo(item);
    if (!isUsable(info))
    {
        BrowserLogger::instance().info("ExtensionService", QStringLiteral("'%1' is not loaded+enabled yet; no URL available")
                                                               .arg(item.name));
        return {};
    }

    return QStringLiteral("illum-ext://%1/%2").arg(info->id(), ext::cleanRel(relativePath));
}

QString ExtensionService::getPopupUrl(const QString &id) const
{
    const int row = indexOfId(id);
    if (row < 0)
        return {};

    const ExtensionItem &item = m_extensions.at(row);
    if (!item.enabled)
        return {};

    const auto info = findEngineInfo(item);
    if (!isUsable(info))
    {
        BrowserLogger::instance().info("ExtensionService", QStringLiteral("getPopupUrl('%1'): extension not ready (loaded=%2 enabled=%3)")
                                                               .arg(item.name,
                                                                    QString::number(info && info->isLoaded()),
                                                                    QString::number(info && info->isEnabled())));
        return {};
    }

    const QUrl popup = info->actionPopupUrl();
    if (popup.isValid() && !popup.isEmpty())
        return rewriteExtensionUrl(popup.toString());

    if (!item.popupPath.isEmpty())
        return buildPageUrl(item, QDir(item.path).relativeFilePath(item.popupPath));

    return {};
}

// toggle, pin, uninstall
void ExtensionService::togglePin(const QString &id)
{
    const int row = indexOfId(id);
    if (row < 0)
        return;

    m_extensions[row].pinned = !m_extensions[row].pinned;
    emit dataChanged(index(row), index(row), {PinnedRole});
    saveToDisk();
}

void ExtensionService::setUserScriptsEnabled(const QString &id, bool enabled)
{
    const int row = indexOfId(id);
    if (row < 0)
        return;

    m_extensions[row].userScriptsEnabled = enabled;
    emit dataChanged(index(row), index(row), {UserScriptsEnabledRole});
    saveToDisk();
    BrowserLogger::instance().info("ExtensionService",
                                    QStringLiteral("userScriptsEnabled set to %1 for %2").arg(enabled ? "true" : "false").arg(id));
}

void ExtensionService::toggleExtension(const QString &id)
{
    const int row = indexOfId(id);
    if (row < 0)
        return;

    m_extensions[row].enabled = !m_extensions[row].enabled;
    emit dataChanged(index(row), index(row), {EnabledRole});
    saveToDisk();

    auto *mgr = ensureManager();
    if (!mgr)
        return;

    const ExtensionItem &item = m_extensions.at(row);
    if (const auto info = findEngineInfo(item))
    {
        syncItemWithEngine(row, *info);
    }
    else if (item.enabled && QFile::exists(item.path + QStringLiteral("/manifest.json")))
    {
        // not loaded into session yet
        mgr->loadExtension(item.path);
    }
}

void ExtensionService::uninstallExtension(const QString &id)
{
    const int row = indexOfId(id);
    if (row < 0)
        return;

    const ExtensionItem item = m_extensions.at(row);
    const QString rootDir = rootDirFor(id);

    // added with load extension
    bool deferDelete = false;
    if (const auto info = findEngineInfo(item))
    {
        if (auto *mgr = ensureManager())
        {
            const QString key = ext::normalizedPath(info->path());
            m_pendingDeletions.insert(key, rootDir);
            mgr->unloadExtension(*info);
            QTimer::singleShot(5000, this, [this, key]()
                               { deletePending(key); });
            deferDelete = true;
        }
    }

    beginRemoveRows(QModelIndex(), row, row);
    m_extensions.removeAt(row);
    endRemoveRows();

    if (!deferDelete)
        removeExtensionDir(rootDir);

    emit countChanged();
    saveToDisk();
}

// address by engine ID
void ExtensionService::installSchemeHandler()
{
    if (m_schemeHandler)
        return;

    auto *p = profile();
    if (!p)
        return;

    m_schemeHandler = new ExtensionSchemeHandler(
        [this](const QString &host)
        { return directoryForEngineId(host); },
        this);
    p->installUrlSchemeHandler(QByteArrayLiteral("illum-ext"), m_schemeHandler);
    BrowserLogger::instance().info("ExtensionService", QStringLiteral("Installed illum-ext:// scheme handler"));
}

QString ExtensionService::directoryForEngineId(const QString &engineId) const
{
    if (engineId.isEmpty())
        return {};

    const auto *mgr = extensionManager();
    if (!mgr)
        return {};

    // bypass the atomicity of the engine snapshot by scanning for a loaded
    // extension whose engine id matches the requested host.
    const auto exts = mgr->extensions();
    for (const auto &ext : exts)
    {
        if (ext.id() == engineId)
            return ext.path();
    }
    return {};
}

void ExtensionService::onUnloadFinished(const QWebEngineExtensionInfo &ext)
{
    BrowserLogger::instance().info("ExtensionService", QStringLiteral("unloadFinished: name=%1 id=%2 loaded=%3")
                                                           .arg(ext.name(), ext.id(), QString::number(ext.isLoaded())));
    deletePending(ext::normalizedPath(ext.path()));
}

void ExtensionService::deletePending(const QString &normalizedPath)
{
    const QString dir = m_pendingDeletions.take(normalizedPath);
    if (!dir.isEmpty())
        removeExtensionDir(dir);
}

// load extensions into profile
void ExtensionService::installToWebEngine()
{
    auto *p = profile();
    if (!p)
    {
        BrowserLogger::instance().warning("ExtensionService", QStringLiteral("No WebEngine profile available"));
        return;
    }
    if (p->isOffTheRecord())
    {
        BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Extensions cannot be loaded into an off-the-record profile"));
        return;
    }

    auto *mgr = ensureManager();
    if (!mgr)
    {
        BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Profile has no extension manager (Qt WebEngine >= 6.10 required)"));
        return;
    }

    // serve through out scheme handler so chrome.runtime / chrome.i18n work in extension pages
    installSchemeHandler();

    const auto engineExts = mgr->extensions();

    for (int i = 0; i < m_extensions.size(); ++i)
    {
        const QString itemPath = m_extensions.at(i).path;
        const bool wantEnabled = m_extensions.at(i).enabled;

        if (!QFile::exists(itemPath + QStringLiteral("/manifest.json")))
        {
            BrowserLogger::instance().warning("ExtensionService", QStringLiteral("manifest.json missing for %1").arg(itemPath));
            continue;
        }

        const QString wanted = ext::normalizedPath(itemPath);
        std::optional<QWebEngineExtensionInfo> match;
        for (const auto &ext : engineExts)
        {
            if (ext::normalizedPath(ext.path()) == wanted)
            {
                match = ext;
                break;
            }
        }

        if (match)
        {
            // already known to manager
            syncItemWithEngine(i, *match);
        }
        else if (wantEnabled)
        {
            BrowserLogger::instance().info("ExtensionService", QStringLiteral("Loading extension from %1").arg(itemPath));
            mgr->loadExtension(itemPath); // -> onLoadFinished() enables it
        }
    }
}

void ExtensionService::onLoadFinished(const QWebEngineExtensionInfo &ext)
{
    BrowserLogger::instance().info("ExtensionService", QStringLiteral("loadFinished: name=%1 id=%2 loaded=%3 enabled=%4 popup=%5 error=%6")
                                                           .arg(ext.name(), ext.id(), QString::number(ext.isLoaded()),
                                                                QString::number(ext.isEnabled()), ext.actionPopupUrl().toString(), ext.error()));

    const int row = indexOfPath(ext.path());
    if (row < 0)
        return; 

    // defer the sync
    const QString path = ext::normalizedPath(ext.path());
    QTimer::singleShot(200, this, [this, path]()
                       {
        const int r = indexOfPath(path);
        if (r < 0)
            return;
        const auto info = findEngineInfo(m_extensions.at(r));
        if (info)
            syncItemWithEngine(r, *info); });
}

// qt loads extensions disabled
void ExtensionService::syncItemWithEngine(int row, const QWebEngineExtensionInfo &info)
{
    if (row < 0 || row >= m_extensions.size())
        return;

    ExtensionItem &item = m_extensions[row];

    auto *mgr = extensionManager();

    // failed to load
    // could show to the user
    if (!info.isLoaded())
    {
        const QString error = info.error();
        if (!error.isEmpty())
        {
            BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Failed to load %1: %2").arg(item.name, error));
            setDownloadStatus(QStringLiteral("Failed to load %1: %2").arg(item.name, error));
        }
        return;
    }

    // Qt WebEngine 6.11.2: setExtensionEnabled() SIGSEGVs on BOTH the enable and
    // disable paths, even deferred (singleShot(0)) with a freshly re-fetched
    // QWebEngineExtensionInfo. Crash lands inside Chromium's
    // ScreenCaptureKitFullscreenModule. Extensions therefore stay
    // loaded-but-disabled forever on this Qt; the app-level toggle remains
    // authoritative only for our UI. Replace with the native QWebEngineScript
    // userscript engine (no extension API involved).
    return;
}

void ExtensionService::confirmEnabled(const QString &id, int attemptsLeft)
{
    const int row = indexOfId(id);
    if (row < 0)
        return;

    const auto info = findEngineInfo(m_extensions.at(row));
    if (isUsable(info))
        return;

    if (attemptsLeft <= 0)
    {
        BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Extension '%1' did not become enabled in time").arg(id));
        return;
    }

    QTimer::singleShot(50, this, [this, id, attemptsLeft]()
                       { confirmEnabled(id, attemptsLeft - 1); });
}