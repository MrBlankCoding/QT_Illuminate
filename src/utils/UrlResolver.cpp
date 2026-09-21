#include "UrlResolver.h"
#include "../core/InternalPageManager.h"
#include <QRegularExpression>

namespace UrlResolver
{

    static bool isIPv4(const QString &s)
    {
        static const QRegularExpression re(R"(^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$)");
        return re.match(s).hasMatch();
    }

    static bool isLocalhost(const QString &s)
    {
        static const QRegularExpression re(
            R"(^localhost(:\d+)?(/.*)?$)", QRegularExpression::CaseInsensitiveOption);
        return re.match(s).hasMatch();
    }

    bool looksLikeHost(const QString &trimmed)
    {
        if (isLocalhost(trimmed) || isIPv4(trimmed))
            return true;
        if (trimmed.contains(' ') || !trimmed.contains('.'))
            return false;
        const int dot = trimmed.indexOf('.');
        return dot > 0 && dot < trimmed.length() - 1;
    }

    QUrl resolve(const QString &input)
    {
        const QString t = input.trimmed();
        if (t.isEmpty())
            return {};

        // Check internal pages
        const QUrl internalUrl = InternalPageManager::resolve(t);
        if (!internalUrl.isEmpty())
            return internalUrl;

        // chrome-extension:// URLs can't render (extensions are disabled in Qt
        // WebEngine 6.11), so rewrite them onto our illum-ext:// scheme.
        if (t.startsWith(QLatin1String("chrome-extension://"), Qt::CaseInsensitive))
        {
            QUrl rewritten(QStringLiteral("illum-ext://") + t.mid(QStringLiteral("chrome-extension://").size()));
            if (rewritten.isValid())
                return rewritten;
            return {};
        }

        if (t.contains("://"))
            return QUrl::fromUserInput(t);
        if (looksLikeHost(t))
            return QUrl::fromUserInput("https://" + t);
        const QString enc = QString::fromUtf8(QUrl::toPercentEncoding(t));
        return QUrl("https://www.google.com/search?q=" + enc);
    }

} // namespace UrlResolver
