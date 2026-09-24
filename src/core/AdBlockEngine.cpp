#include "AdBlockEngine.h"

#include <QSet>
#include <QUrl>

namespace
{

// is word
bool isTokenChar(QChar c)
{
    const char16_t u = c.unicode();
    return (u >= 'a' && u <= 'z') || (u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9') || u == '%';
}

// "^" matches anything but a letter, digit or one of _-.%
bool isSeparator(QChar c)
{
    const char16_t u = c.unicode();
    return !((u >= 'a' && u <= 'z') || (u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9') || u == '_' || u == '-' || u == '.' || u == '%');
}

// does pattern match the start of text
// "*" is any run of characters, "^" a separator or the end of the url
bool globMatch(QStringView pattern, QStringView text, bool anchorEnd)
{
    qsizetype p = 0, t = 0;
    qsizetype starP = -1, starT = 0;
    while (true)
    {
        if (p == pattern.size())
        {
            if (!anchorEnd || t == text.size())
                return true;
        }
        else if (pattern[p] == u'*')
        {
            starP = p++;
            starT = t;
            continue;
        }
        else if (t < text.size() && (pattern[p] == u'^' ? isSeparator(text[t]) : pattern[p] == text[t]))
        {
            ++p;
            ++t;
            continue;
        }
        else if (pattern[p] == u'^' && t == text.size())
        {
            ++p;
            continue;
        }
        // mismatch: let the last "*" swallow one more character
        // ouuu shii
        if (starP < 0 || starT >= text.size())
            return false;
        p = starP + 1;
        t = ++starT;
    }
}

bool hostMatchesDomain(const QString &host, const QString &domain)
{
    return host == domain || (host.endsWith(domain) && host.size() > domain.size() && host[host.size() - domain.size() - 1] == u'.');
}

bool hostInList(const QString &host, const QStringList &domains)
{
    for (const QString &d : domains)
        if (hostMatchesDomain(host, d))
            return true;
    return false;
}

quint32 typeFromOption(QStringView name)
{
    using E = AdBlockEngine;
    if (name == u"script")
        return E::Script;
    if (name == u"image")
        return E::Image;
    if (name == u"stylesheet" || name == u"css")
        return E::Stylesheet;
    if (name == u"object")
        return E::Object;
    if (name == u"xmlhttprequest" || name == u"xhr")
        return E::XmlHttpRequest;
    if (name == u"subdocument" || name == u"frame")
        return E::Subdocument;
    if (name == u"ping")
        return E::Ping;
    if (name == u"media")
        return E::Media;
    if (name == u"font")
        return E::Font;
    if (name == u"websocket")
        return E::WebSocket;
    if (name == u"other")
        return E::Other;
    return 0;
}

} // namespace

void AdBlockEngine::addList(QStringView text)
{
    qsizetype start = 0;
    while (start < text.size())
    {
        qsizetype end = text.indexOf(u'\n', start);
        if (end < 0)
            end = text.size();
        addRule(text.sliced(start, end - start).trimmed());
        start = end + 1;
    }
}

void AdBlockEngine::addRule(QStringView line)
{
    if (line.isEmpty() || line.startsWith(u'!') || line.startsWith(u'['))
        return;
    if (addCosmeticRule(line))
        return;

    Rule rule;
    const bool exception = line.startsWith(u"@@");
    QStringView body = exception ? line.sliced(2) : line;

    // options come after the last "$", unless that "$" is part of a /regex/
    bool documentRule = false, popupRule = false, elemHide = false, genericHide = false;
    quint32 types = 0, excludedTypes = 0;
    const qsizetype dollar = body.lastIndexOf(u'$');
    const bool dollarInRegex = body.startsWith(u'/') && dollar > 0 && body.lastIndexOf(u'/') > dollar;
    if (dollar >= 0 && !dollarInRegex)
    {
        for (QStringView option : body.sliced(dollar + 1).split(u','))
        {
            const bool negated = option.startsWith(u'~');
            if (negated)
                option = option.sliced(1);
            const qsizetype eq = option.indexOf(u'=');
            const QStringView name = eq < 0 ? option : option.first(eq);
            const QStringView value = eq < 0 ? QStringView() : option.sliced(eq + 1);

            if (name == u"third-party" || name == u"3p")
                rule.thirdParty = negated ? 0 : 1;
            else if (name == u"first-party" || name == u"1p")
                rule.thirdParty = negated ? 1 : 0;
            else if (name == u"match-case")
                rule.matchCase = true;
            else if (name == u"important")
                ; // there's no priority between lists here, so nothing to do
            else if (name == u"domain")
            {
                for (QStringView d : value.split(u'|', Qt::SkipEmptyParts))
                {
                    if (d.startsWith(u'~'))
                        rule.excludeDomains.append(d.sliced(1).toString().toLower());
                    else
                        rule.includeDomains.append(d.toString().toLower());
                }
            }
            else if (name == u"document")
                documentRule = !negated;
            else if (name == u"popup")
                popupRule = !negated;
            else if (name == u"elemhide" || name == u"ehide")
                elemHide = true;
            else if (name == u"generichide" || name == u"ghide")
                genericHide = true;
            else if (const quint32 type = typeFromOption(name))
                (negated ? excludedTypes : types) |= type;
            else
                return; // $csp, $redirect, $removeparam, ...: not something we can apply
        }
        body = body.first(dollar);
    }

    // "$popup" alone applies only to new windows; "$popup,script" also to scripts
    const bool requestRule = !popupRule || types != 0;
    if (types == 0)
        types = AllTypes;
    rule.types = types & ~excludedTypes;
    if (rule.types == 0)
        return;

    if ((elemHide || genericHide || documentRule) && !exception)
        return;

    if (body.size() > 2 && body.startsWith(u'/') && body.endsWith(u'/'))
    {
        rule.anchor = Anchor::Regex;
        rule.pattern = body.sliced(1, body.size() - 2).toString();
        rule.regex.setPattern(rule.pattern);
        if (!rule.matchCase)
            rule.regex.setPatternOptions(QRegularExpression::CaseInsensitiveOption);
        if (!rule.regex.isValid())
            return;
        rule.regex.optimize();
    }
    else
    {
        if (body.startsWith(u"||"))
        {
            rule.anchor = Anchor::Host;
            body = body.sliced(2);
        }
        else if (body.startsWith(u'|'))
        {
            rule.anchor = Anchor::Start;
            body = body.sliced(1);
        }
        if (body.endsWith(u'|'))
        {
            rule.anchorEnd = true;
            body.chop(1);
        }
        // leading/trailing wildcards change nothing for a substring match
        if (rule.anchor == Anchor::None)
            while (body.startsWith(u'*'))
                body = body.sliced(1);
        if (!rule.anchorEnd)
            while (body.endsWith(u'*'))
                body.chop(1);
        rule.pattern = rule.matchCase ? body.toString() : body.toString().toLower();
    }

    m_rules.append(std::move(rule));
    const int ruleIndex = int(m_rules.size() - 1);
    if (documentRule || elemHide || genericHide)
    {
        if (documentRule)
            index(m_document, ruleIndex);
        if (elemHide)
            index(m_elemHide, ruleIndex);
        if (genericHide)
            index(m_genericHide, ruleIndex);
        return;
    }
    if (popupRule)
        index(exception ? m_popupAllow : m_popup, ruleIndex);
    if (requestRule)
        index(exception ? m_allow : m_block, ruleIndex);
}

// "example.com,~shop.example.com##.ad" / "##.ad" / "example.com#@#.ad"
bool AdBlockEngine::addCosmeticRule(QStringView line)
{
    qsizetype hash = line.indexOf(u'#');
    while (hash >= 0 && hash + 1 < line.size())
    {
        const QStringView rest = line.sliced(hash + 1);
        qsizetype selectorStart = -1;
        bool exception = false;
        if (rest.startsWith(u'#'))
            selectorStart = hash + 2;
        else if (rest.startsWith(u"@#"))
        {
            selectorStart = hash + 3;
            exception = true;
        }
        else if (rest.startsWith(u"?#") || rest.startsWith(u"@?#") || rest.startsWith(u"$#") || rest.startsWith(u"@$#")
                 || rest.startsWith(u"%#") || rest.startsWith(u"@%#") || rest.startsWith(u"+js"))
            return true; // procedural cosmetics and scriptlets: recognised, not supported

        if (selectorStart >= 0)
        {
            const QString selector = line.sliced(selectorStart).trimmed().toString();
            if (selector.isEmpty() || selector.contains(u'{') || selector.contains(u'}') || selector.startsWith(u"+js(") || selector.startsWith(u'^') || selector.contains(u":-abp-") || selector.contains(u":has-text(") || selector.contains(u":xpath(")
                || selector.contains(u":style(") || selector.contains(u":remove(") || selector.contains(u":upward(")
                || selector.contains(u":matches-") || selector.contains(u":min-text-length("))
                return true;

            QStringList include, exclude;
            for (QStringView d : line.first(hash).split(u',', Qt::SkipEmptyParts))
            {
                d = d.trimmed();
                if (d.startsWith(u'~'))
                    exclude.append(d.sliced(1).toString().toLower());
                else
                    include.append(d.toString().toLower());
            }

            ++m_cosmeticCount;
            if (exception)
            {
                if (include.isEmpty() && m_genericSet.remove(selector))
                    m_genericSelectors.removeAll(selector);
                for (const QString &d : include)
                    m_siteExceptions[d].insert(selector);
                return true;
            }
            if (include.isEmpty())
            {
                if (!m_genericSet.contains(selector))
                {
                    m_genericSet.insert(selector);
                    m_genericSelectors.append(selector);
                }
            }
            else
            {
                for (const QString &d : include)
                    m_siteSelectors[d].append(selector);
            }
            for (const QString &d : exclude)
                m_siteExceptions[d].insert(selector);
            return true;
        }
        hash = line.indexOf(u'#', hash + 1);
    }
    return false;
}

void AdBlockEngine::index(RuleSet &set, int ruleIndex)
{
    const Rule &rule = m_rules[ruleIndex];
    if (rule.anchor == Anchor::Regex)
    {
        set.generic.append(ruleIndex);
        return;
    }
    const QString pattern = rule.pattern.toLower();

    // "||ads.example.com^..." : the host is complete when a separator follows it
    if (rule.anchor == Anchor::Host)
    {
        qsizetype end = 0;
        while (end < pattern.size() && !QStringView(u"/^*:?|").contains(pattern[end]))
            ++end;
        if (end > 0 && end < pattern.size() && pattern[end] != u'*')
        {
            set.byHost[pattern.first(end)].append(ruleIndex);
            return;
        }
    }

    QStringView best;
    qsizetype i = 0;
    while (i < pattern.size())
    {
        if (!isTokenChar(pattern[i]))
        {
            ++i;
            continue;
        }
        const qsizetype start = i;
        while (i < pattern.size() && isTokenChar(pattern[i]))
            ++i;
        const bool leftClosed = start > 0 ? pattern[start - 1] != u'*' : rule.anchor != Anchor::None;
        const bool rightClosed = i < pattern.size() ? pattern[i] != u'*' : rule.anchorEnd;
        if (leftClosed && rightClosed && i - start > best.size())
            best = QStringView(pattern).sliced(start, i - start);
    }
    if (best.size() >= 2)
        set.byToken[best.toString()].append(ruleIndex);
    else
        set.generic.append(ruleIndex);
}

bool AdBlockEngine::shouldBlock(const Request &request) const
{
    return matchesSet(m_block, request, true) && !matchesSet(m_allow, request, true);
}

bool AdBlockEngine::isPageAllowed(const QString &pageUrl, const QString &pageHost) const
{
    return matchesPage(m_document, pageUrl, pageHost);
}

bool AdBlockEngine::matchesPage(const RuleSet &set, const QString &pageUrl, const QString &pageHost) const
{
    if (set.isEmpty())
        return false;
    Request page;
    page.url = pageUrl;
    page.urlLower = pageUrl.toLower();
    page.host = pageHost;
    page.firstPartyHost = pageHost;
    return matchesSet(set, page, false);
}

bool AdBlockEngine::shouldBlockPopup(const QUrl &url, const QUrl &openerUrl) const
{
    const Request request = makeRequest(url, openerUrl, AllTypes);
    return matchesSet(m_popup, request, true) && !matchesSet(m_popupAllow, request, true);
}

AdBlockEngine::Cosmetic AdBlockEngine::cosmeticFor(const QString &pageUrl, const QString &pageHost) const
{
    Cosmetic result;
    if (matchesPage(m_document, pageUrl, pageHost) || matchesPage(m_elemHide, pageUrl, pageHost))
    {
        result.off = true;
        return result;
    }
    result.noGeneric = matchesPage(m_genericHide, pageUrl, pageHost);

    // rules for the host and each parent domain
    QSet<QString> exceptions;
    QList<const QStringList *> selectorLists;
    QStringView host(pageHost);
    while (!host.isEmpty())
    {
        const QString key = host.toString();
        if (const auto it = m_siteExceptions.constFind(key); it != m_siteExceptions.cend())
            exceptions.unite(*it);
        if (const auto it = m_siteSelectors.constFind(key); it != m_siteSelectors.cend())
            selectorLists.append(&*it);
        const qsizetype dot = host.indexOf(u'.');
        if (dot < 0)
            break;
        host = host.sliced(dot + 1);
    }

    for (const QStringList *list : selectorLists)
        for (const QString &selector : *list)
            if (!exceptions.contains(selector))
                result.hide.append(selector);
    if (!result.noGeneric)
        for (const QString &selector : exceptions)
            if (m_genericSet.contains(selector))
                result.unhideGeneric.append(selector);
    return result;
}

bool AdBlockEngine::matchesSet(const RuleSet &set, const Request &request, bool checkOptions) const
{
    QStringView host(request.host);
    while (!host.isEmpty())
    {
        const auto it = set.byHost.constFind(host.toString());
        if (it != set.byHost.cend())
            for (int r : *it)
                if (matchesRule(m_rules[r], request, checkOptions))
                    return true;
        const qsizetype dot = host.indexOf(u'.');
        if (dot < 0)
            break;
        host = host.sliced(dot + 1);
    }

    if (!set.byToken.isEmpty())
    {
        const QString &url = request.urlLower;
        QSet<QStringView> seen;
        qsizetype i = 0;
        while (i < url.size())
        {
            if (!isTokenChar(url[i]))
            {
                ++i;
                continue;
            }
            const qsizetype start = i;
            while (i < url.size() && isTokenChar(url[i]))
                ++i;
            const QStringView token = QStringView(url).sliced(start, i - start);
            if (token.size() < 2 || seen.contains(token))
                continue;
            seen.insert(token);
            const auto it = set.byToken.constFind(token.toString());
            if (it != set.byToken.cend())
                for (int r : *it)
                    if (matchesRule(m_rules[r], request, checkOptions))
                        return true;
        }
    }

    for (int r : set.generic)
        if (matchesRule(m_rules[r], request, checkOptions))
            return true;
    return false;
}

bool AdBlockEngine::matchesRule(const Rule &rule, const Request &request, bool checkOptions) const
{
    if (checkOptions)
    {
        if (!(rule.types & request.type))
            return false;
        if (rule.thirdParty >= 0 && bool(rule.thirdParty) != request.thirdParty)
            return false;
    }
    if (!rule.includeDomains.isEmpty() && !hostInList(request.firstPartyHost, rule.includeDomains))
        return false;
    if (!rule.excludeDomains.isEmpty() && hostInList(request.firstPartyHost, rule.excludeDomains))
        return false;
    return matchesPattern(rule, request);
}

bool AdBlockEngine::matchesPattern(const Rule &rule, const Request &request) const
{
    const QStringView url(rule.matchCase ? request.url : request.urlLower);
    const QStringView pattern(rule.pattern);

    switch (rule.anchor)
    {
    case Anchor::Regex:
        return rule.regex.matchView(QStringView(request.url)).hasMatch();

    case Anchor::Start:
        return globMatch(pattern, url, rule.anchorEnd);

    case Anchor::Host:
    {
        const qsizetype hostStart = url.indexOf(u"://");
        if (hostStart < 0)
            return false;
        const qsizetype begin = hostStart + 3;
        const qsizetype end = begin + request.host.size();
        for (qsizetype p = begin; p < end; ++p)
        {
            if ((p == begin || url[p - 1] == u'.') && globMatch(pattern, url.sliced(p), rule.anchorEnd))
                return true;
        }
        return false;
    }

    case Anchor::None:
    {
        if (pattern.isEmpty())
            return true;
        qsizetype literal = 0;
        while (literal < pattern.size() && pattern[literal] != u'*' && pattern[literal] != u'^')
            ++literal;
        if (literal == 0)
        {
            for (qsizetype p = 0; p <= url.size(); ++p)
                if (globMatch(pattern, url.sliced(p), rule.anchorEnd))
                    return true;
            return false;
        }
        const QStringView head = pattern.first(literal);
        for (qsizetype p = url.indexOf(head); p >= 0; p = url.indexOf(head, p + 1))
            if (globMatch(pattern, url.sliced(p), rule.anchorEnd))
                return true;
        return false;
    }
    }
    return false;
}

QString AdBlockEngine::registrableDomain(const QString &host)
{
    if (host.contains(u':')) // IPv6
        return host;
    const QList<QStringView> labels = QStringView(host).split(u'.', Qt::SkipEmptyParts);
    if (labels.size() <= 2)
        return host;
    const QStringView last = labels.last();
    if (last.front().isDigit()) // IPv4
        return host;

    // two-part public suffixes under country codes: co.uk, com.au, ne.jp, ...
    // i wish this wasnt hard coded
    static const QSet<QString> secondLevel = {
        "co", "com", "net", "org", "gov", "edu", "ac", "ne", "or", "go", "gv", "ltd", "plc", "sch", "nhs", "mil", "nic", "info", "biz",
    };
    int keep = 2;
    if (last.size() == 2 && secondLevel.contains(labels[labels.size() - 2].toString()))
        keep = 3;
    if (labels.size() <= keep)
        return host;
    QString result;
    for (qsizetype i = labels.size() - keep; i < labels.size(); ++i)
    {
        if (!result.isEmpty())
            result += u'.';
        result += labels[i];
    }
    return result;
}

quint32 AdBlockEngine::contentType(QWebEngineUrlRequestInfo::ResourceType type)
{
    using R = QWebEngineUrlRequestInfo;
    switch (type)
    {
    case R::ResourceTypeMainFrame:
    case R::ResourceTypeNavigationPreloadMainFrame:
        return 0;
    case R::ResourceTypeSubFrame:
    case R::ResourceTypeNavigationPreloadSubFrame:
        return Subdocument;
    case R::ResourceTypeStylesheet:
        return Stylesheet;
    case R::ResourceTypeScript:
    case R::ResourceTypeWorker:
    case R::ResourceTypeSharedWorker:
    case R::ResourceTypeServiceWorker:
        return Script;
    case R::ResourceTypeImage:
    case R::ResourceTypeFavicon:
        return Image;
    case R::ResourceTypeFontResource:
        return Font;
    case R::ResourceTypeObject:
    case R::ResourceTypePluginResource:
        return Object;
    case R::ResourceTypeMedia:
        return Media;
    case R::ResourceTypeXhr:
    case R::ResourceTypeJson:
        return XmlHttpRequest;
    case R::ResourceTypePing:
    case R::ResourceTypeCspReport:
        return Ping;
    case R::ResourceTypeWebSocket:
        return WebSocket;
    default:
        return Other;
    }
}

AdBlockEngine::Request AdBlockEngine::makeRequest(const QUrl &url, const QUrl &firstPartyUrl, quint32 type)
{
    Request request;
    request.url = url.toString(QUrl::FullyEncoded);
    request.urlLower = request.url.toLower();
    request.host = url.host().toLower();
    request.firstPartyHost = firstPartyUrl.host().toLower();
    request.thirdParty = !request.firstPartyHost.isEmpty() && registrableDomain(request.host) != registrableDomain(request.firstPartyHost);
    request.type = type;
    return request;
}
