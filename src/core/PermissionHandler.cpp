#include "PermissionHandler.h"
#include "../utils/BrowserLogger.h"

#include <QCoreApplication>
#include <algorithm>
#include <QDir>
#include <QGuiApplication>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>

#if defined(Q_OS_LINUX)
#include <QProcess>
#elif defined(Q_OS_WIN)
#include <QDesktopServices>
#endif

namespace {
const QString kGroup = QStringLiteral("permissions");
#if defined(Q_OS_LINUX)
const QString kDesktopFile = QStringLiteral("qt-illuminate.desktop");
#elif defined(Q_OS_WIN)
const QString kProgId = QStringLiteral("QT_Illuminate.URL");
const QString kAppName = QStringLiteral("QT_Illuminate");
#endif
}

PermissionHandler::PermissionHandler(QObject *parent)
    : QObject(parent),
      m_settings(new QSettings(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                               + QDir::separator() + QStringLiteral("permissions.ini"),
                               QSettings::IniFormat, this))
{
    // default browser and OS privacy choices are made in system dialogs or
    // Settings; re-check when the user comes back
    if (qGuiApp)
    {
        connect(qGuiApp, &QGuiApplication::applicationStateChanged, this,
                [this](Qt::ApplicationState state) {
                    if (state != Qt::ApplicationActive)
                        return;
                    if (m_defaultBrowserChecked)
                        refreshDefaultBrowser();
                    emit systemAccessChanged();
                });
    }
}

// ── site permissions ────────────────────────────────────────────────

QWebEnginePermission::PermissionType PermissionHandler::toType(int v)
{
    return static_cast<QWebEnginePermission::PermissionType>(v);
}

QString PermissionHandler::key(const QUrl &origin, int type) const
{
    return QStringLiteral("%1/%2/%3").arg(kGroup, origin.host(), QString::number(type));
}

QString PermissionHandler::labelForType(int type) const
{
    using T = QWebEnginePermission::PermissionType;
    switch (toType(type)) {
    case T::MediaAudioCapture:        return QStringLiteral("Microphone");
    case T::MediaVideoCapture:        return QStringLiteral("Camera");
    case T::MediaAudioVideoCapture:   return QStringLiteral("Camera and Microphone");
    case T::DesktopVideoCapture:      return QStringLiteral("Screen capture");
    case T::DesktopAudioVideoCapture: return QStringLiteral("Screen capture");
    case T::MouseLock:                return QStringLiteral("Mouse lock");
    case T::Notifications:            return QStringLiteral("Notifications");
    case T::Geolocation:              return QStringLiteral("Location");
    case T::ClipboardReadWrite:       return QStringLiteral("Clipboard");
    case T::LocalFontsAccess:         return QStringLiteral("Fonts");
    case T::Unsupported:
    default: return QStringLiteral("Permission");
    }
}

bool PermissionHandler::resolve(QWebEnginePermission permission) const
{
    const int type = static_cast<int>(permission.permissionType());
    switch (decision(permission.origin(), type)) {
    case Allow: permission.grant(); return true;
    case Deny:  permission.deny();  return true;
    default:    return false;
    }
}

void PermissionHandler::respond(QWebEnginePermission permission, bool allow, bool remember)
{
    if (allow)
        permission.grant();
    else
        permission.deny();
    storeDecision(permission.origin(), static_cast<int>(permission.permissionType()), allow, remember);
}

int PermissionHandler::decision(const QUrl &origin, int type) const
{
    const QString v = m_settings->value(key(origin, type)).toString();
    if (v == QStringLiteral("allow")) return Allow;
    if (v == QStringLiteral("deny"))  return Deny;
    return Ask;
}

void PermissionHandler::storeDecision(const QUrl &origin, int type, bool allow, bool remember)
{
    if (!remember)
        return;
    m_settings->setValue(key(origin, type), allow ? QStringLiteral("allow") : QStringLiteral("deny"));
    BrowserLogger::instance().info("Permissions",
        (allow ? "Remembered allow " : "Remembered deny ")
        + labelForType(type) + " for " + origin.host());
    emit decisionsChanged();
}

void PermissionHandler::forget(const QUrl &origin, int type)
{
    m_settings->remove(key(origin, type));
    emit decisionsChanged();
}

void PermissionHandler::forgetAll()
{
    m_settings->remove(kGroup);
    emit decisionsChanged();
}

QVariantList PermissionHandler::rememberedDecisions() const
{
    QVariantList out;
    m_settings->beginGroup(kGroup);
    for (const QString &host : m_settings->childGroups())
    {
        m_settings->beginGroup(host);
        for (const QString &typeKey : m_settings->childKeys())
        {
            const int type = typeKey.toInt();
            out.append(QVariantMap{
                {QStringLiteral("host"), host},
                {QStringLiteral("type"), type},
                {QStringLiteral("label"), labelForType(type)},
                {QStringLiteral("allow"), m_settings->value(typeKey).toString() == QStringLiteral("allow")},
            });
        }
        m_settings->endGroup();
    }
    m_settings->endGroup();
    return out;
}

// ── OS access ──────────────────────────────────────────────────────

QList<PermissionHandler::SystemResource> PermissionHandler::resourcesForType(int type)
{
    using T = QWebEnginePermission::PermissionType;
    switch (toType(type)) {
    case T::MediaAudioCapture:        return {Microphone};
    case T::MediaVideoCapture:        return {Camera};
    case T::MediaAudioVideoCapture:   return {Camera, Microphone};
    case T::DesktopVideoCapture:      return {ScreenCapture};
    case T::DesktopAudioVideoCapture: return {ScreenCapture, Microphone};
    case T::Geolocation:              return {Location};
    default:                          return {};
    }
}

int PermissionHandler::systemAccess(int resource) const
{
    return platformSystemAccess(static_cast<SystemResource>(resource));
}

int PermissionHandler::systemAccessForType(int type) const
{
    SystemAccess worst = Granted;
    for (SystemResource r : resourcesForType(type))
        worst = std::max(worst, platformSystemAccess(r));
    return worst;
}

int PermissionHandler::blockedResourceForType(int type) const
{
    for (SystemResource r : resourcesForType(type))
        if (platformSystemAccess(r) == Denied)
            return r;
    return -1;
}

void PermissionHandler::requestSystemAccess(int resource)
{
    platformRequestSystemAccess(static_cast<SystemResource>(resource));
}

void PermissionHandler::openSystemSettings(int resource)
{
    platformOpenSystemSettings(static_cast<SystemResource>(resource));
}

QString PermissionHandler::labelForResource(int resource) const
{
    switch (static_cast<SystemResource>(resource)) {
    case Camera:        return QStringLiteral("Camera");
    case Microphone:    return QStringLiteral("Microphone");
    case Location:      return QStringLiteral("Location");
    case ScreenCapture: return QStringLiteral("Screen recording");
    }
    return QString();
}

// ── default browser ────────────────────────────────────────────────

bool PermissionHandler::isDefaultBrowser() const
{
    if (!m_defaultBrowserChecked)
        const_cast<PermissionHandler *>(this)->refreshDefaultBrowser();
    return m_isDefaultBrowser;
}

bool PermissionHandler::defaultBrowserBusy() const
{
    return m_defaultBrowserBusy;
}

bool PermissionHandler::defaultBrowserOpensSystemSettings() const
{
#if defined(Q_OS_WIN)
    return true;
#else
    return false;
#endif
}

void PermissionHandler::refreshDefaultBrowser()
{
    m_defaultBrowserChecked = true;
    setIsDefaultBrowser(platformIsDefaultBrowser());
}

void PermissionHandler::makeDefaultBrowser()
{
    if (m_defaultBrowserBusy)
        return;
    setDefaultBrowserBusy(true);
    platformMakeDefaultBrowser();
}

void PermissionHandler::setIsDefaultBrowser(bool value)
{
    if (m_isDefaultBrowser == value)
        return;
    m_isDefaultBrowser = value;
    emit isDefaultBrowserChanged();
}

void PermissionHandler::setDefaultBrowserBusy(bool value)
{
    if (m_defaultBrowserBusy == value)
        return;
    m_defaultBrowserBusy = value;
    emit defaultBrowserBusyChanged();
}

void PermissionHandler::finishDefaultBrowserRequest(bool ok, const QString &error)
{
    setDefaultBrowserBusy(false);
    refreshDefaultBrowser();
    if (!ok)
    {
        BrowserLogger::instance().warning("Permissions", error);
        emit defaultBrowserFailed(error);
    }
}

// ── platform: Linux ────────────────────────────────────────────────

#if defined(Q_OS_LINUX)

// no OS-level gate for desktop apps; portals prompt on their own
PermissionHandler::SystemAccess PermissionHandler::platformSystemAccess(SystemResource)
{
    return Granted;
}

void PermissionHandler::platformRequestSystemAccess(SystemResource)
{
    emit systemAccessChanged();
}

void PermissionHandler::platformOpenSystemSettings(SystemResource)
{
}

bool PermissionHandler::platformIsDefaultBrowser()
{
    QProcess p;
    p.start(QStringLiteral("xdg-settings"),
            {QStringLiteral("check"), QStringLiteral("default-web-browser"), kDesktopFile});
    if (!p.waitForFinished(2000))
        return false;
    return p.readAllStandardOutput().trimmed() == "yes";
}

void PermissionHandler::platformMakeDefaultBrowser()
{
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p](int code, QProcess::ExitStatus status) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        finishDefaultBrowserRequest(ok, ok ? QString()
                                           : QStringLiteral("xdg-settings failed: ")
                                                 + QString::fromLocal8Bit(p->readAllStandardError()).trimmed());
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p](QProcess::ProcessError err) {
        if (err != QProcess::FailedToStart)
            return;
        finishDefaultBrowserRequest(false, QStringLiteral("xdg-settings is not installed"));
        p->deleteLater();
    });
    p->start(QStringLiteral("xdg-settings"),
             {QStringLiteral("set"), QStringLiteral("default-web-browser"), kDesktopFile});
}

// ── platform: Windows ──────────────────────────────────────────────

#elif defined(Q_OS_WIN)

namespace {
QString consentStoreKey(PermissionHandler::SystemResource resource)
{
    switch (resource) {
    case PermissionHandler::Camera:     return QStringLiteral("webcam");
    case PermissionHandler::Microphone: return QStringLiteral("microphone");
    case PermissionHandler::Location:   return QStringLiteral("location");
    default:                            return QString();
    }
}
}

PermissionHandler::SystemAccess PermissionHandler::platformSystemAccess(SystemResource resource)
{
    const QString store = consentStoreKey(resource);
    if (store.isEmpty())
        return Granted;
    // the global switch, then the one covering non-Store desktop apps
    const QString base = QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\") + store;
    for (const QString &path : {base, base + QStringLiteral("\\NonPackaged")})
    {
        QSettings s(path, QSettings::NativeFormat);
        if (s.value(QStringLiteral("Value")).toString() == QStringLiteral("Deny"))
            return Denied;
    }
    return Granted;
}

// Windows never prompts desktop apps; access is a Settings toggle
void PermissionHandler::platformRequestSystemAccess(SystemResource resource)
{
    if (platformSystemAccess(resource) == Denied)
        platformOpenSystemSettings(resource);
    emit systemAccessChanged();
}

void PermissionHandler::platformOpenSystemSettings(SystemResource resource)
{
    QString page;
    switch (resource) {
    case Camera:        page = QStringLiteral("privacy-webcam"); break;
    case Microphone:    page = QStringLiteral("privacy-microphone"); break;
    case Location:      page = QStringLiteral("privacy-location"); break;
    case ScreenCapture: page = QStringLiteral("privacy"); break;
    }
    QDesktopServices::openUrl(QUrl(QStringLiteral("ms-settings:") + page));
}

bool PermissionHandler::platformIsDefaultBrowser()
{
    QSettings choice(QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\Shell\\Associations\\UrlAssociations\\https\\UserChoice"),
                     QSettings::NativeFormat);
    return choice.value(QStringLiteral("ProgId")).toString() == kProgId;
}

void PermissionHandler::platformMakeDefaultBrowser()
{
    // Windows won't let apps set this themselves; register as a candidate
    // under HKCU and open Default Apps filtered to us
    const QString exe = QDir::toNativeSeparators(QCoreApplication::applicationFilePath());

    QSettings progId(QStringLiteral("HKEY_CURRENT_USER\\Software\\Classes\\") + kProgId,
                     QSettings::NativeFormat);
    progId.setValue(QStringLiteral("Default"), QStringLiteral("QT_Illuminate URL"));
    progId.setValue(QStringLiteral("URL Protocol"), QString());
    progId.setValue(QStringLiteral("shell/open/command/Default"),
                    QStringLiteral("\"%1\" \"%2\"").arg(exe, QStringLiteral("%1")));

    QSettings caps(QStringLiteral("HKEY_CURRENT_USER\\Software\\") + kAppName + QStringLiteral("\\Capabilities"),
                   QSettings::NativeFormat);
    caps.setValue(QStringLiteral("ApplicationName"), kAppName);
    caps.setValue(QStringLiteral("ApplicationDescription"), QStringLiteral("A Qt WebEngine browser"));
    caps.setValue(QStringLiteral("URLAssociations/http"), kProgId);
    caps.setValue(QStringLiteral("URLAssociations/https"), kProgId);

    QSettings registered(QStringLiteral("HKEY_CURRENT_USER\\Software\\RegisteredApplications"),
                         QSettings::NativeFormat);
    registered.setValue(kAppName, QStringLiteral("Software\\") + kAppName + QStringLiteral("\\Capabilities"));

    progId.sync();
    caps.sync();
    registered.sync();

    const bool opened = QDesktopServices::openUrl(
        QUrl(QStringLiteral("ms-settings:defaultapps?registeredAppUser=") + kAppName));
    // the choice happens in Settings; re-check when the user comes back
    QTimer::singleShot(0, this, [this, opened]() {
        finishDefaultBrowserRequest(opened, QStringLiteral("Could not open Windows Default Apps settings"));
    });
}

// ── platform: other (macOS lives in PermissionHandler_mac.mm) ──────

#elif !defined(Q_OS_MACOS)

PermissionHandler::SystemAccess PermissionHandler::platformSystemAccess(SystemResource)
{
    return Granted;
}

void PermissionHandler::platformRequestSystemAccess(SystemResource)
{
    emit systemAccessChanged();
}

void PermissionHandler::platformOpenSystemSettings(SystemResource)
{
}

bool PermissionHandler::platformIsDefaultBrowser()
{
    return false;
}

void PermissionHandler::platformMakeDefaultBrowser()
{
    QTimer::singleShot(0, this, [this]() {
        finishDefaultBrowserRequest(false, QStringLiteral("Setting the default browser isn't supported on this platform"));
    });
}

#endif
