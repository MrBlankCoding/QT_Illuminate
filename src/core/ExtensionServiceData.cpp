#include "ExtensionService.h"
#include "../utils/BrowserLogger.h"
#include "ExtensionServiceInternals.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSaveFile>

namespace
{
    // Chrome-style human readable permission labels; unknown names pass through.
    QString humanPermission(const QString &p)
    {
        static const QHash<QString, QString> m = {
            {QStringLiteral("activeTab"), QStringLiteral("Read and change all your data on the website you are on")},
            {QStringLiteral("alarms"), QStringLiteral("Manage background tasks")},
            {QStringLiteral("bookmarks"), QStringLiteral("Read and change your bookmarks")},
            {QStringLiteral("clipboardRead"), QStringLiteral("Read data you copy and paste")},
            {QStringLiteral("clipboardWrite"), QStringLiteral("Modify data you copy and paste")},
            {QStringLiteral("cookies"), QStringLiteral("Read and change your cookies")},
            {QStringLiteral("contextMenus"), QStringLiteral("Show custom context menus")},
            {QStringLiteral("declarativeNetRequest"), QStringLiteral("Block and hide network requests")},
            {QStringLiteral("downloads"), QStringLiteral("Manage your downloads")},
            {QStringLiteral("geolocation"), QStringLiteral("Know your location")},
            {QStringLiteral("history"), QStringLiteral("Read your browsing history")},
            {QStringLiteral("management"), QStringLiteral("Manage other extensions")},
            {QStringLiteral("notifications"), QStringLiteral("Display notifications")},
            {QStringLiteral("offscreen"), QStringLiteral("Create offscreen web pages")},
            {QStringLiteral("scripting"), QStringLiteral("Inject code and modify websites")},
            {QStringLiteral("storage"), QStringLiteral("Store data on your device")},
            {QStringLiteral("tabs"), QStringLiteral("Read your browsing history and activity")},
            {QStringLiteral("userScripts"), QStringLiteral("Run user scripts (contents not reviewed)")},
            {QStringLiteral("webRequest"), QStringLiteral("Read and change your internet traffic")},
        };
        return m.value(p, p);
    }

    bool readJsonObject(const QString &path, QJsonObject *out)
    {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly))
            return false;

        QByteArray raw = f.readAll();
        if (raw.startsWith("\xEF\xBB\xBF"))
            raw.remove(0, 3);

        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject())
            return false;

        *out = doc.object();
        return true;
    }

    // _locales/<locale>/messages.json for __MSG_xxx__ resolution.
    QJsonObject loadLocaleMessages(const QString &dirPath, const QString &defaultLocale)
    {
        const QDir localesDir(dirPath + QStringLiteral("/_locales"));

        QStringList candidates;
        if (!defaultLocale.isEmpty())
            candidates << defaultLocale;
        candidates << QStringLiteral("en") << QStringLiteral("en_US");
        candidates << localesDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);

        for (const QString &loc : std::as_const(candidates))
        {
            QJsonObject messages;
            if (readJsonObject(localesDir.filePath(loc) + QStringLiteral("/messages.json"), &messages))
                return messages;
        }
        return {};
    }

    // picks icon from extension manifest
    QString pickIcon(const QJsonValue &v)
    {
        if (v.isString())
            return v.toString();
        if (!v.isObject())
            return {};

        const QJsonObject map = v.toObject();
        QString best;
        int bestSize = -1;

        for (auto it = map.begin(); it != map.end(); ++it)
        {
            bool ok = false;
            const int size = it.key().toInt(&ok);
            const QString candidate = it.value().toString();
            if (!ok || candidate.isEmpty())
                continue;

            bool better = false;
            if (best.isEmpty())
            {
                better = true;
            }
            else
            {
                const bool bestBigEnough = bestSize >= 32;
                const bool candBigEnough = size >= 32;
                if (candBigEnough && bestBigEnough)
                    better = size < bestSize;
                else if (candBigEnough != bestBigEnough)
                    better = candBigEnough;
                else
                    better = size > bestSize;
            }
            if (better)
            {
                best = candidate;
                bestSize = size;
            }
        }

        if (best.isEmpty() && !map.isEmpty())
            best = map.begin().value().toString();
        return best;
    }
} // namespace


QString ExtensionService::rootDirFor(const QString &id) const
{
    return ext::isValidId(id) ? m_baseDir + QStringLiteral("/") + id : QString();
}

QString ExtensionService::stagingRoot() const
{
    return m_baseDir + QStringLiteral("/.staging");
}

// only delete things in our extension folder
void ExtensionService::removeExtensionDir(const QString &dir) const
{
    if (dir.isEmpty())
        return;

    const QString base = QDir::cleanPath(m_baseDir) + QStringLiteral("/");
    if (!QDir::cleanPath(dir).startsWith(base))
    {
        BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Refusing to delete directory outside the extensions folder: %1").arg(dir));
        return;
    }
    QDir(dir).removeRecursively();
}

bool ExtensionService::locateManifestDir(const QString &root, QString *relDir)
{
    if (QFile::exists(root + QStringLiteral("/manifest.json")))
    {
        relDir->clear();
        return true;
    }

    const QStringList subdirs = QDir(root).entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &sub : subdirs)
    {
        if (sub == QLatin1String("__MACOSX"))
            continue;
        if (QFile::exists(root + QStringLiteral("/") + sub + QStringLiteral("/manifest.json")))
        {
            *relDir = sub;
            return true;
        }
    }
    return false;
}

bool ExtensionService::parseManifest(const QString &dirPath, ManifestInfo &out)
{
    QJsonObject obj;
    if (!readJsonObject(dirPath + QStringLiteral("/manifest.json"), &obj))
        return false;

    out.manifestVersion = obj.value(QStringLiteral("manifest_version")).toInt(0);
    const QString defaultLocale = obj.value(QStringLiteral("default_locale")).toString();

    // __MSG_key__ -> _locales/<locale>/messages.json
    QJsonObject messages;
    bool messagesLoaded = false;
    auto resolveMsg = [&](const QString &str) -> QString
    {
        if (!str.startsWith(QLatin1String("__MSG_")) || !str.endsWith(QLatin1String("__")) || str.size() <= 8)
            return str;

        const QString key = str.mid(6, str.size() - 8);
        if (!messagesLoaded)
        {
            messagesLoaded = true;
            messages = loadLocaleMessages(dirPath, defaultLocale);
        }
        for (auto it = messages.begin(); it != messages.end(); ++it)
        {
            if (it.key().compare(key, Qt::CaseInsensitive) == 0)
            {
                const QString msg = it.value().toObject().value(QStringLiteral("message")).toString();
                if (!msg.isEmpty())
                    return msg;
            }
        }
        return str;
    };

    const QString name = resolveMsg(obj.value(QStringLiteral("name")).toString());
    if (!name.isEmpty())
        out.name = name;

    const QString version = obj.value(QStringLiteral("version")).toString();
    if (!version.isEmpty())
        out.version = version;

    out.description = resolveMsg(obj.value(QStringLiteral("description")).toString());

    out.author = obj.value(QStringLiteral("author")).toString();
    out.homepageUrl = obj.value(QStringLiteral("homepage_url")).toString();

    const QJsonArray perms = obj.value(QStringLiteral("permissions")).toArray();
    for (const QJsonValue &p : perms)
    {
        const QString name = p.toString();
        if (name.isEmpty())
            continue;
        out.permissions.append(humanPermission(name));
        if (name == QLatin1String("userScripts"))
            out.hasUserScripts = true;
    }

    const QJsonArray hostPerms = obj.value(QStringLiteral("host_permissions")).toArray();
    for (const QJsonValue &hp : hostPerms)
    {
        const QString host = hp.toString();
        if (!host.isEmpty())
            out.hostPermissions.append(host);
    }

    // only MV3
    QJsonObject action = obj.value(QStringLiteral("action")).toObject();
    out.popupRel = ext::cleanRel(action.value(QStringLiteral("default_popup")).toString());

    out.iconRel = ext::cleanRel(pickIcon(action.value(QStringLiteral("default_icon"))));
    if (out.iconRel.isEmpty())
        out.iconRel = ext::cleanRel(pickIcon(obj.value(QStringLiteral("icons"))));

    return true;
}

void ExtensionService::loadFromDisk()
{
    QFile f(m_baseDir + QStringLiteral("/extensions.json"));
    if (!f.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isArray())
        return;

    beginResetModel();
    m_extensions.clear();

    const QJsonArray arr = doc.array();
    for (const QJsonValue &v : arr)
    {
        if (!v.isObject())
            continue;

        const QJsonObject o = v.toObject();
        ExtensionItem item;
        item.id = o.value(QStringLiteral("id")).toString();
        item.name = o.value(QStringLiteral("name")).toString();
        item.version = o.value(QStringLiteral("version")).toString();
        item.description = o.value(QStringLiteral("description")).toString();
        item.path = o.value(QStringLiteral("path")).toString();
        item.iconPath = o.value(QStringLiteral("iconPath")).toString();
        item.popupPath = o.value(QStringLiteral("popupPath")).toString();
        item.author = o.value(QStringLiteral("author")).toString();
        item.homepageUrl = o.value(QStringLiteral("homepageUrl")).toString();
        const QJsonArray savedPerms = o.value(QStringLiteral("permissions")).toArray();
        for (const QJsonValue &p : savedPerms)
            item.permissions.append(p.toString());
        const QJsonArray savedHosts = o.value(QStringLiteral("hostPermissions")).toArray();
        for (const QJsonValue &h : savedHosts)
            item.hostPermissions.append(h.toString());
        item.hasUserScripts = o.value(QStringLiteral("hasUserScripts")).toBool(false);
        item.userScriptsEnabled = o.value(QStringLiteral("userScriptsEnabled")).toBool(false);
        item.sizeBytes = o.value(QStringLiteral("sizeBytes")).toDouble(qint64(0));
        item.enabled = o.value(QStringLiteral("enabled")).toBool(true);
        item.pinned = o.value(QStringLiteral("pinned")).toBool(true);

        if (item.id.isEmpty() || !QFile::exists(item.path + QStringLiteral("/manifest.json")))
            continue;

        // Entries saved before author/homepage/size landed won't have them;
        // backfill on the fly from the manifest + disk rather than forcing a
        // reinstall.
        ManifestInfo miBackfill;
        if (item.author.isEmpty() || item.homepageUrl.isEmpty() || item.description.isEmpty()
            || item.permissions.isEmpty() || item.sizeBytes == 0)
        {
            if (parseManifest(item.path, miBackfill))
            {
                if (item.author.isEmpty())
                    item.author = miBackfill.author;
                if (item.homepageUrl.isEmpty())
                    item.homepageUrl = miBackfill.homepageUrl;
                if (item.description.isEmpty())
                    item.description = miBackfill.description;
                if (item.permissions.isEmpty())
                    item.permissions = miBackfill.permissions;
                if (item.hasUserScripts == false)
                    item.hasUserScripts = miBackfill.hasUserScripts;
            }
            if (item.sizeBytes == 0)
                item.sizeBytes = ext::dirSizeBytes(item.path);
        }
        m_extensions.append(item);
    }
    endResetModel();
}

void ExtensionService::saveToDisk()
{
    QJsonArray arr;
    for (const auto &item : std::as_const(m_extensions))
    {
        QJsonObject o;
        o[QStringLiteral("id")] = item.id;
        o[QStringLiteral("name")] = item.name;
        o[QStringLiteral("version")] = item.version;
        o[QStringLiteral("description")] = item.description;
        o[QStringLiteral("path")] = item.path;
        o[QStringLiteral("iconPath")] = item.iconPath;
        o[QStringLiteral("popupPath")] = item.popupPath;
        o[QStringLiteral("author")] = item.author;
        o[QStringLiteral("homepageUrl")] = item.homepageUrl;
        QJsonArray permsArr;
        for (const QString &p : item.permissions)
            permsArr.append(p);
        o[QStringLiteral("permissions")] = permsArr;
        QJsonArray hostsArr;
        for (const QString &h : item.hostPermissions)
            hostsArr.append(h);
        o[QStringLiteral("hostPermissions")] = hostsArr;
        o[QStringLiteral("hasUserScripts")] = item.hasUserScripts;
        o[QStringLiteral("userScriptsEnabled")] = item.userScriptsEnabled;
        o[QStringLiteral("sizeBytes")] = item.sizeBytes;
        o[QStringLiteral("enabled")] = item.enabled;
        o[QStringLiteral("pinned")] = item.pinned;
        arr.append(o);
    }

    QSaveFile f(m_baseDir + QStringLiteral("/extensions.json"));
    if (!f.open(QIODevice::WriteOnly))
    {
        BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Could not open extensions.json for writing: %1").arg(f.errorString()));
        return;
    }
    f.write(QJsonDocument(arr).toJson(QJsonDocument::Indented));
    if (!f.commit())
        BrowserLogger::instance().warning("ExtensionService", QStringLiteral("Could not save extensions.json: %1").arg(f.errorString()));
}