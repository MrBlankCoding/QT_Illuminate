#ifndef WEBVERSION_H
#define WEBVERSION_H

#include <QString>
#include <QByteArray>
#include <QVariantMap>
#include <QtWebEngineCore/qtwebenginecoreglobal.h>

inline QString chromiumVersion()
{
    return QString::fromLatin1(qWebEngineChromiumVersion());
}
// web version
inline QString chromeUserAgent()
{
    const QString major = chromiumVersion().section('.', 0, 0);
#if defined(Q_OS_MACOS)
    const QString os = QStringLiteral("Macintosh; Intel Mac OS X 10_15_7");
#elif defined(Q_OS_WIN)
    const QString os = QStringLiteral("Windows NT 10.0; Win64; x64");
#else
    const QString os = QStringLiteral("X11; Linux x86_64");
#endif
    return QStringLiteral(
        "Mozilla/5.0 (%1) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/%2.0.0.0 Safari/537.36").arg(os, major);
}

inline QVariantMap chromeBrandVersions()
{
    const QString full = chromiumVersion();
    return {
        {QStringLiteral("Google Chrome"), full},
        {QStringLiteral("Chromium"), full},
        {QStringLiteral("Not=A?Brand"), QStringLiteral("24.0.0.0")},
    };
}

#endif
