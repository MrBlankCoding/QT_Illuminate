#ifndef WEBVERSION_H
#define WEBVERSION_H

#include <QString>
#include <QByteArray>
#include <QtWebEngineCore/qtwebenginecoreglobal.h>

inline QString chromiumVersion()
{
    return QString::fromLatin1(qWebEngineChromiumVersion());
}

inline QString chromeUserAgent()
{
    const QString major = chromiumVersion().section('.', 0, 0);
    return QStringLiteral(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/%1.0.0.0 Safari/537.36").arg(major);
}

#endif