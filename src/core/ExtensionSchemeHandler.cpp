#include "ExtensionSchemeHandler.h"

#include <QBuffer>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QMimeDatabase>
#include <QRegularExpression>
#include <QSysInfo>
#include <QUrl>
#include <QWebEngineUrlRequestJob>

#include <utility>

static const char kChromeShim[] = "";

namespace
{

    // nothing here is served
    constexpr QLatin1String kReservedPrefix("__illum__/");
    constexpr QLatin1String kShimPath("__illum__/chrome_shim.js");
    constexpr QLatin1String kBootstrapPath("__illum__/bootstrap.js");

    const QByteArray kJsMime = QByteArrayLiteral("text/javascript; charset=utf-8");
    const QByteArray kHtmlMime = QByteArrayLiteral("text/html; charset=utf-8");

    // job doesnt own device, but device is deleted when job is destroyed.
    void replyWithDevice(QWebEngineUrlRequestJob *job, const QByteArray &mime, QIODevice *device)
    {
        QObject::connect(job, &QObject::destroyed, device, &QObject::deleteLater);
        job->reply(mime, device);
    }

    void replyWithBytes(QWebEngineUrlRequestJob *job, const QByteArray &mime, const QByteArray &data)
    {
        auto *buffer = new QBuffer;
        buffer->setData(data);
        buffer->open(QIODevice::ReadOnly);
        replyWithDevice(job, mime, buffer);
    }

    // web content shouldnt be allowed to touch extensions
    bool isWebInitiator(const QUrl &initiator)
    {
        if (initiator.isEmpty() || !initiator.isValid())
            return false;
        const QString s = initiator.scheme();
        return s == QLatin1String("http") || s == QLatin1String("https") || s == QLatin1String("file") || s == QLatin1String("ftp");
    }

    // reserves path for extension bootstrap and shim injection, and for the extension scheme itself
    QString resolveInside(const QString &canonicalRoot, const QString &relative)
    {
        QFileInfo fi(canonicalRoot + QLatin1Char('/') + relative);
        if (fi.isDir())
            fi.setFile(QDir(fi.absoluteFilePath()).filePath(QStringLiteral("index.html")));

        const QString canonical = fi.canonicalFilePath(); // empty if it doesn't exist
        if (canonical.isEmpty() || !QFileInfo(canonical).isFile())
            return {};
        const QString prefix = canonicalRoot.endsWith(QLatin1Char('/'))
                                   ? canonicalRoot
                                   : canonicalRoot + QLatin1Char('/');
        return (canonical.size() > prefix.size() && canonical.startsWith(prefix))
                   ? canonical
                   : QString();
    }

    // file reading
    // what if its a big file?

    QByteArray readSmallFile(const QString &path, qint64 maxBytes = 8 * 1024 * 1024)
    {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly) || f.size() > maxBytes)
            return {};
        QByteArray data = f.readAll();
        if (data.startsWith("\xEF\xBB\xBF")) // UTF-8 BOM
            data.remove(0, 3);
        return data;
    }

    QJsonObject readJsonObject(const QString &path)
    {
        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(readSmallFile(path), &err);
        return (err.error == QJsonParseError::NoError && doc.isObject()) ? doc.object() : QJsonObject();
    }

    // bootsrap data

    QString systemLocaleName() // "en_US" style
    {
        const QString name = QLocale::system().name();
        return (name.isEmpty() || name == QLatin1String("C")) ? QStringLiteral("en_US") : name;
    }

    QString platformOs()
    {
#if defined(Q_OS_MACOS)
        return QStringLiteral("mac");
#elif defined(Q_OS_WIN)
        return QStringLiteral("win");
#else
        return QStringLiteral("linux");
#endif
    }

    QString platformArch() // values as used by chrome.runtime.getPlatformInfo()
    {
        const QString arch = QSysInfo::currentCpuArchitecture();
        if (arch == QLatin1String("arm64"))
            return QStringLiteral("arm64");
        if (arch.startsWith(QLatin1String("arm")))
            return QStringLiteral("arm");
        if (arch == QLatin1String("x86_64"))
            return QStringLiteral("x86-64");
        if (arch == QLatin1String("i386"))
            return QStringLiteral("x86-32");
        return arch;
    }

    // merge locals 
    QJsonObject loadMessages(const QString &root, const QJsonObject &manifest)
    {
        static const QRegularExpression safeName(QStringLiteral("^[A-Za-z0-9_-]+$"));

        QString defaultLocale = manifest.value(QStringLiteral("default_locale")).toString();
        if (defaultLocale.isEmpty())
            defaultLocale = QStringLiteral("en");

        const QString full = systemLocaleName();
        const QString lang = full.section(QLatin1Char('_'), 0, 0);

        QStringList candidates; // lowest priority first
        for (const QString &loc : {defaultLocale, lang, full})
        {
            if (!candidates.contains(loc))
                candidates.append(loc);
        }

        QJsonObject merged;
        for (const QString &loc : std::as_const(candidates))
        {
            if (!safeName.match(loc).hasMatch()) // default_locale comes from the manifest
                continue;
            const QJsonObject m = readJsonObject(root + QStringLiteral("/_locales/") + loc + QStringLiteral("/messages.json"));
            for (auto it = m.constBegin(); it != m.constEnd(); ++it)
                merged.insert(it.key().toLower(), it.value());
        }
        return merged;
    }

    QByteArray buildBootstrap(const QString &host, const QString &root)
    {
        const QJsonObject manifest = readJsonObject(root + QStringLiteral("/manifest.json"));

        QJsonObject platform;
        platform.insert(QStringLiteral("os"), platformOs());
        platform.insert(QStringLiteral("arch"), platformArch());

        QJsonObject boot;
        boot.insert(QStringLiteral("id"), host);
        boot.insert(QStringLiteral("manifest"), manifest);
        boot.insert(QStringLiteral("messages"), loadMessages(root, manifest));
        boot.insert(QStringLiteral("uiLanguage"), systemLocaleName().replace(QLatin1Char('_'), QLatin1Char('-')));
        boot.insert(QStringLiteral("platform"), platform);

        // json is valid js 
        return "window.__illum=" + QJsonDocument(boot).toJson(QJsonDocument::Compact) + ";\n";
    }

    // inject shim into html
    qsizetype endOfOpeningTag(const QByteArray &html, const char *tag)
    {
        const qsizetype len = qsizetype(qstrlen(tag));
        for (qsizetype i = html.indexOf('<'); i >= 0 && i + len + 1 < html.size();
             i = html.indexOf('<', i + 1))
        {
            if (qstrnicmp(html.constData() + i + 1, tag, len) != 0)
                continue;
            const char next = html.at(i + 1 + len);
            const bool boundary = next == '>' || next == '/' || next == ' ' || next == '\t' || next == '\n' || next == '\r' || next == '\f';
            if (!boundary)
                continue;
            const qsizetype gt = html.indexOf('>', i);
            if (gt >= 0)
                return gt + 1;
        }
        return -1;
    }

    QByteArray injectChromeShim(const QByteArray &html)
    {
        static const QByteArray tags =
            "<script src=\"/__illum__/bootstrap.js\"></script>"
            "<script src=\"/__illum__/chrome_shim.js\"></script>";

        // prefer top of head so it happens faster 
        qsizetype pos = endOfOpeningTag(html, "head");
        if (pos < 0)
            pos = endOfOpeningTag(html, "html");
        if (pos < 0)
            pos = endOfOpeningTag(html, "!doctype");

        QByteArray out = html;
        out.insert(pos < 0 ? 0 : pos, tags);
        return out;
    }


    bool isHtmlFile(const QString &path)
    {
        const QString suffix = QFileInfo(path).suffix().toLower();
        return suffix == QLatin1String("html") || suffix == QLatin1String("htm");
    }

    // mime database varies by platform
    QByteArray mimeTypeFor(const QString &path)
    {
        static const QHash<QString, QByteArray> known = {
            {QStringLiteral("html"), "text/html; charset=utf-8"},
            {QStringLiteral("htm"), "text/html; charset=utf-8"},
            {QStringLiteral("js"), "text/javascript; charset=utf-8"},
            {QStringLiteral("mjs"), "text/javascript; charset=utf-8"},
            {QStringLiteral("css"), "text/css; charset=utf-8"},
            {QStringLiteral("json"), "application/json; charset=utf-8"},
            {QStringLiteral("map"), "application/json; charset=utf-8"},
            {QStringLiteral("txt"), "text/plain; charset=utf-8"},
            {QStringLiteral("svg"), "image/svg+xml"},
            {QStringLiteral("wasm"), "application/wasm"},
            {QStringLiteral("woff"), "font/woff"},
            {QStringLiteral("woff2"), "font/woff2"},
            {QStringLiteral("ttf"), "font/ttf"},
        };

        const auto it = known.constFind(QFileInfo(path).suffix().toLower());
        if (it != known.constEnd())
            return it.value();

        const QByteArray name = QMimeDatabase()
                                    .mimeTypeForFile(path, QMimeDatabase::MatchExtension)
                                    .name()
                                    .toLatin1();
        return name.isEmpty() ? QByteArrayLiteral("application/octet-stream") : name;
    }

} // namespace

// scheme handler
ExtensionSchemeHandler::ExtensionSchemeHandler(Resolver resolver, QObject *parent)
    : QWebEngineUrlSchemeHandler(parent), m_resolver(std::move(resolver))
{
    QFile chromeShimFile(QDir::currentPath() + "/resources/js/chrome_shim.js");
    if (chromeShimFile.open(QIODevice::ReadOnly | QIODevice::Text))
    {
        m_chromeShimJs = chromeShimFile.readAll();
        chromeShimFile.close();
    }
    else
    {
        qWarning("ExtensionSchemeHandler: Could not open chrome_shim.js");
    }
}

void ExtensionSchemeHandler::requestStarted(QWebEngineUrlRequestJob *job)
{
    const QUrl url = job->requestUrl();
    if (url.scheme() != scheme())
    {
        job->fail(QWebEngineUrlRequestJob::UrlInvalid);
        return;
    }

    const QByteArray method = job->requestMethod();
    if (method != "GET" && method != "HEAD")
    {
        job->fail(QWebEngineUrlRequestJob::RequestDenied);
        return;
    }

    if (isWebInitiator(job->initiator()))
    {
        job->fail(QWebEngineUrlRequestJob::RequestDenied);
        return;
    }

    // url.path() is already percent-decoded; anything sneaky like "%2e%2e" is
    // caught by the canonical-path check in resolveInside().
    QString relative = url.path();
    while (relative.startsWith(QLatin1Char('/')))
        relative.remove(0, 1);

    // shim is the same for every extension, so it doesn't need a host
    if (relative == kShimPath)
    {
        replyWithBytes(job, kJsMime, m_chromeShimJs);
        return;
    }

    const QString host = url.host();
    const QString root = m_resolver ? QDir(m_resolver(host)).canonicalPath() : QString();
    if (root.isEmpty())
    {
        job->fail(QWebEngineUrlRequestJob::UrlNotFound);
        return;
    }

    if (relative == kBootstrapPath)
    {
        replyWithBytes(job, kJsMime, buildBootstrap(host, root));
        return;
    }
    if (relative.startsWith(kReservedPrefix))
    { // never fall through to real files
        job->fail(QWebEngineUrlRequestJob::UrlNotFound);
        return;
    }

    const QString path = resolveInside(root, relative);
    if (path.isEmpty())
    {
        job->fail(QWebEngineUrlRequestJob::UrlNotFound);
        return;
    }

    if (isHtmlFile(path))
    {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
        {
            job->fail(QWebEngineUrlRequestJob::UrlNotFound);
            return;
        }
        replyWithBytes(job, kHtmlMime, injectChromeShim(file.readAll()));
        return;
    }

    // stream from disk
    auto *file = new QFile(path);
    if (!file->open(QIODevice::ReadOnly))
    {
        delete file;
        job->fail(QWebEngineUrlRequestJob::UrlNotFound);
        return;
    }
    replyWithDevice(job, mimeTypeFor(path), file);
}