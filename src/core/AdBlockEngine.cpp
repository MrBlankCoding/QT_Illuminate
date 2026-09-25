#include "AdBlockEngine.h"

#include <QSet>
#include <QUrl>
#include <QVarLengthArray>

#include <algorithm>

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

bool hostMatchesDomain(QStringView host, QStringView domain)
{
    return host == domain || (host.endsWith(domain) && host.size() > domain.size() && host[host.size() - domain.size() - 1] == u'.');
}

// FNV-1a; keys are already lowercase
quint64 hashKey(QStringView s)
{
    quint64 h = 14695981039346656037ull;
    for (QChar c : s)
    {
        h ^= c.unicode();
        h *= 1099511628211ull;
    }
    return h;
}

template <typename Entry>
auto entriesFor(const std::vector<Entry> &entries, quint64 key)
{
    return std::equal_range(entries.begin(), entries.end(), Entry{key, 0});
}

template <typename T>
void release(T &container)
{
    T().swap(container);
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

AdBlockEngine::Span AdBlockEngine::store(QStringView s)
{
    const Span span{quint32(m_text.size()), quint32(s.size())};
    m_text.append(s);
    return span;
}

quint32 AdBlockEngine::intern(QStringView s)
{
    const quint64 key = hashKey(s);
    const auto it = m_intern.constFind(key);
    if (it != m_intern.cend() && string(*it) == s)
        return *it;
    const quint32 id = quint32(m_strings.size());
    m_strings.push_back(store(s));
    // a 64-bit collision just means this text isn't deduplicated
    if (it == m_intern.cend())
        m_intern.insert(key, id);
    return id;
}

void AdBlockEngine::addList(QStringView text)
{
    Q_ASSERT(!m_finalized);
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

void AdBlockEngine::finalize()
{
    for (RuleSet *set : {&m_block, &m_allow, &m_document, &m_popup, &m_popupAllow, &m_elemHide, &m_genericHide})
    {
        std::sort(set->byHost.begin(), set->byHost.end());
        std::sort(set->byToken.begin(), set->byToken.end());
        set->byHost.shrink_to_fit();
        set->byToken.shrink_to_fit();
        set->generic.shrink_to_fit();
    }
    // stable: a site's selectors keep their list order
    std::stable_sort(m_siteSelectors.begin(), m_siteSelectors.end());
    std::sort(m_siteExceptions.begin(), m_siteExceptions.end());
    m_generic.assign(m_genericIds.cbegin(), m_genericIds.cend());
    std::sort(m_generic.begin(), m_generic.end());

    m_siteSelectors.shrink_to_fit();
    m_siteExceptions.shrink_to_fit();
    m_strings.shrink_to_fit();
    m_rules.shrink_to_fit();
    m_ruleDomains.shrink_to_fit();
    m_regexes.squeeze();
    m_text.squeeze();
    release(m_intern);
    release(m_genericIds);
    m_finalized = true;
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

    // views into line; only stored once the rule is known to be usable
    QVarLengthArray<QStringView, 8> includeDomains, excludeDomains;

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
                        excludeDomains.append(d.sliced(1));
                    else
                        includeDomains.append(d);
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
        QRegularExpression regex(body.sliced(1, body.size() - 2).toString());
        if (!rule.matchCase)
            regex.setPatternOptions(QRegularExpression::CaseInsensitiveOption);
        if (!regex.isValid())
            return;
        regex.optimize();
        rule.regex = qint32(m_regexes.size());
        m_regexes.append(std::move(regex));
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
        rule.pattern = rule.matchCase ? store(body) : store(body.toString().toLower());
    }

    rule.domains = quint32(m_ruleDomains.size());
    rule.includeCount = quint16(std::min<qsizetype>(includeDomains.size(), 0xffff));
    rule.excludeCount = quint16(std::min<qsizetype>(excludeDomains.size(), 0xffff));
    for (qsizetype i = 0; i < rule.includeCount; ++i)
        m_ruleDomains.push_back(intern(includeDomains[i].toString().toLower()));
    for (qsizetype i = 0; i < rule.excludeCount; ++i)
        m_ruleDomains.push_back(intern(excludeDomains[i].toString().toLower()));

    m_rules.push_back(rule);
    const quint32 ruleIndex = quint32(m_rules.size() - 1);
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
            const QStringView selector = line.sliced(selectorStart).trimmed();
            if (selector.isEmpty() || selector.contains(u'{') || selector.contains(u'}') || selector.startsWith(u"+js(") || selector.startsWith(u'^') || selector.contains(u":-abp-") || selector.contains(u":has-text(") || selector.contains(u":xpath(")
                || selector.contains(u":style(") || selector.contains(u":remove(") || selector.contains(u":upward(")
                || selector.contains(u":matches-") || selector.contains(u":min-text-length("))
                return true;

            QVarLengthArray<quint64, 8> include, exclude;
            for (QStringView d : line.first(hash).split(u',', Qt::SkipEmptyParts))
            {
                d = d.trimmed();
                if (d.startsWith(u'~'))
                    exclude.append(hashKey(d.sliced(1).toString().toLower()));
                else
                    include.append(hashKey(d.toString().toLower()));
            }

            ++m_cosmeticCount;
            const quint32 id = intern(selector);
            if (exception)
            {
                if (include.isEmpty())
                    m_genericIds.remove(id);
                for (quint64 d : include)
                    m_siteExceptions.push_back({d, id});
                return true;
            }
            if (include.isEmpty())
                m_genericIds.insert(id);
            else
                for (quint64 d : include)
                    m_siteSelectors.push_back({d, id});
            for (quint64 d : exclude)
                m_siteExceptions.push_back({d, id});
            return true;
        }
        hash = line.indexOf(u'#', hash + 1);
    }
    return false;
}

void AdBlockEngine::index(RuleSet &set, quint32 ruleIndex)
{
    const Rule &rule = m_rules[ruleIndex];
    if (rule.anchor == Anchor::Regex)
    {
        set.generic.push_back(ruleIndex);
        return;
    }
    const QString pattern = view(rule.pattern).toString().toLower();

    // "||ads.example.com^..." : the host is complete when a separator follows it
    if (rule.anchor == Anchor::Host)
    {
        qsizetype end = 0;
        while (end < pattern.size() && !QStringView(u"/^*:?|").contains(pattern[end]))
            ++end;
        if (end > 0 && end < pattern.size() && pattern[end] != u'*')
        {
            set.byHost.push_back({hashKey(QStringView(pattern).first(end)), ruleIndex});
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
        set.byToken.push_back({hashKey(best), ruleIndex});
    else
        set.generic.push_back(ruleIndex);
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

QStringList AdBlockEngine::genericSelectors() const
{
    QStringList selectors;
    selectors.reserve(qsizetype(m_generic.size()));
    for (quint32 id : m_generic)
        selectors.append(string(id).toString());
    return selectors;
}

AdBlockEngine::Cosmetic AdBlockEngine::cosmeticFor(const QString &pageUrl, const QString &pageHost) const
{
    Q_ASSERT(m_finalized);
    Cosmetic result;
    if (matchesPage(m_document, pageUrl, pageHost) || matchesPage(m_elemHide, pageUrl, pageHost))
    {
        result.off = true;
        return result;
    }
    result.noGeneric = matchesPage(m_genericHide, pageUrl, pageHost);

    // rules for the host and each parent domain
    QVarLengthArray<quint64, 8> keys;
    QVarLengthArray<quint32, 32> exceptions;
    QStringView host(pageHost);
    while (!host.isEmpty())
    {
        const quint64 key = hashKey(host);
        keys.append(key);
        const auto [begin, end] = entriesFor(m_siteExceptions, key);
        for (auto it = begin; it != end; ++it)
            exceptions.append(it->value);
        const qsizetype dot = host.indexOf(u'.');
        if (dot < 0)
            break;
        host = host.sliced(dot + 1);
    }
    std::sort(exceptions.begin(), exceptions.end());
    exceptions.erase(std::unique(exceptions.begin(), exceptions.end()), exceptions.end());

    for (quint64 key : keys)
    {
        const auto [begin, end] = entriesFor(m_siteSelectors, key);
        for (auto it = begin; it != end; ++it)
            if (!std::binary_search(exceptions.cbegin(), exceptions.cend(), it->value))
                result.hide.append(string(it->value).toString());
    }
    if (!result.noGeneric)
        for (quint32 id : exceptions)
            if (std::binary_search(m_generic.cbegin(), m_generic.cend(), id))
                result.unhideGeneric.append(string(id).toString());
    return result;
}

bool AdBlockEngine::matchesSet(const RuleSet &set, const Request &request, bool checkOptions) const
{
    Q_ASSERT(m_finalized);
    if (!set.byHost.empty())
    {
        QStringView host(request.host);
        while (!host.isEmpty())
        {
            const auto [begin, end] = entriesFor(set.byHost, hashKey(host));
            for (auto it = begin; it != end; ++it)
                if (matchesRule(m_rules[it->value], request, checkOptions))
                    return true;
            const qsizetype dot = host.indexOf(u'.');
            if (dot < 0)
                break;
            host = host.sliced(dot + 1);
        }
    }

    if (!set.byToken.empty())
    {
        const QString &url = request.urlLower;
        QVarLengthArray<quint64, 64> seen;
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
            if (i - start < 2)
                continue;
            const quint64 key = hashKey(QStringView(url).sliced(start, i - start));
            if (std::find(seen.cbegin(), seen.cend(), key) != seen.cend())
                continue;
            seen.append(key);
            const auto [begin, end] = entriesFor(set.byToken, key);
            for (auto it = begin; it != end; ++it)
                if (matchesRule(m_rules[it->value], request, checkOptions))
                    return true;
        }
    }

    for (quint32 r : set.generic)
        if (matchesRule(m_rules[r], request, checkOptions))
            return true;
    return false;
}

bool AdBlockEngine::hostInDomains(quint32 first, quint32 count, QStringView host) const
{
    for (quint32 i = first; i < first + count; ++i)
        if (hostMatchesDomain(host, string(m_ruleDomains[i])))
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
    if (rule.includeCount && !hostInDomains(rule.domains, rule.includeCount, request.firstPartyHost))
        return false;
    if (rule.excludeCount && hostInDomains(rule.domains + rule.includeCount, rule.excludeCount, request.firstPartyHost))
        return false;
    return matchesPattern(rule, request);
}

bool AdBlockEngine::matchesPattern(const Rule &rule, const Request &request) const
{
    const QStringView url(rule.matchCase ? request.url : request.urlLower);
    const QStringView pattern = view(rule.pattern);

    switch (rule.anchor)
    {
    case Anchor::Regex:
        return m_regexes[rule.regex].matchView(QStringView(request.url)).hasMatch();

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
