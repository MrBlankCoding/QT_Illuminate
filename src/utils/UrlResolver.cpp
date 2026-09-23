#include "UrlResolver.h"
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
        return dot > 0 && dot < trimmed.size() - 1;
    }

    QUrl resolve(const QString &input)
    {
        const QString t = input.trimmed();
        if (t.isEmpty())
            return {};

        if (t.contains("://"))
            return QUrl::fromUserInput(t);
        if (looksLikeHost(t))
            return QUrl::fromUserInput("https://" + t);
        const QString enc = QString::fromUtf8(QUrl::toPercentEncoding(t));
        return QUrl("https://www.google.com/search?q=" + enc);
    }

} // namespace UrlResolver
