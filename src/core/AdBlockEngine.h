#pragma once

#include <QHash>
#include <QList>
#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QStringView>
#include <QWebEngineUrlRequestInfo>

#include <vector>

// filter matcher
// similar to ad block +
//
// ~140k rules live here for the whole session, so the layout is flat:
// every string sits in one pool, rules are small PODs, and the lookup
// tables are sorted (hash, rule) arrays instead of QHash<QString, QList>.
class AdBlockEngine
{
public:
    enum ContentType : quint32
    {
        Other = 1u << 0,
        Script = 1u << 1,
        Image = 1u << 2,
        Stylesheet = 1u << 3,
        Object = 1u << 4,
        XmlHttpRequest = 1u << 5,
        Subdocument = 1u << 6,
        Ping = 1u << 7,
        Media = 1u << 8,
        Font = 1u << 9,
        WebSocket = 1u << 10,
        AllTypes = (1u << 11) - 1,
    };

    struct Request
    {
        QString url;
        QString urlLower;
        QString host;
        QString firstPartyHost;
        bool thirdParty = false;
        quint32 type = Other;
    };

    struct Cosmetic
    {
        bool off = false;
        bool noGeneric = false;
        QStringList hide;
        QStringList unhideGeneric;
    };

    void addList(QStringView text);
    // sorts the lookup tables and drops parse-only state.
    // call once after the last addList(), before matching
    void finalize();

    bool shouldBlock(const Request &request) const;
    bool isPageAllowed(const QString &pageUrl, const QString &pageHost) const;
    bool shouldBlockPopup(const QUrl &url, const QUrl &openerUrl) const;
    Cosmetic cosmeticFor(const QString &pageUrl, const QString &pageHost) const;
    QStringList genericSelectors() const;

    int ruleCount() const { return int(m_rules.size()) + m_cosmeticCount; }
    static QString registrableDomain(const QString &host);
    // 0 when the request type is never blocked (top-level page loads)
    static quint32 contentType(QWebEngineUrlRequestInfo::ResourceType type);
    static Request makeRequest(const QUrl &url, const QUrl &firstPartyUrl, quint32 type);

private:
    enum class Anchor : quint8
    {
        None,
        Start,
        Host,
        Regex,
    };

    // a slice of m_text
    struct Span
    {
        quint32 offset = 0;
        quint32 size = 0;
    };

    struct Rule
    {
        Span pattern;            // empty for regex rules
        quint32 types = AllTypes;
        quint32 domains = 0;     // first entry in m_ruleDomains: includes, then excludes
        quint16 includeCount = 0;
        quint16 excludeCount = 0;
        qint32 regex = -1;       // index into m_regexes
        Anchor anchor = Anchor::None;
        bool anchorEnd = false;
        bool matchCase = false;
        qint8 thirdParty = -1;
    };

    // key is a hash of a host or token; collisions only cost an extra matchesRule()
    struct Entry
    {
        quint64 key;
        quint32 value;
        bool operator<(const Entry &o) const { return key < o.key; }
    };

    struct RuleSet
    {
        std::vector<Entry> byHost;
        std::vector<Entry> byToken;
        std::vector<quint32> generic;

        bool isEmpty() const { return byHost.empty() && byToken.empty() && generic.empty(); }
    };

    void addRule(QStringView line);
    bool addCosmeticRule(QStringView line);
    void index(RuleSet &set, quint32 ruleIndex);
    bool matchesSet(const RuleSet &set, const Request &request, bool checkOptions) const;
    bool matchesRule(const Rule &rule, const Request &request, bool checkOptions) const;
    bool matchesPattern(const Rule &rule, const Request &request) const;
    bool matchesPage(const RuleSet &set, const QString &pageUrl, const QString &pageHost) const;
    bool hostInDomains(quint32 first, quint32 count, QStringView host) const;

    Span store(QStringView s);
    // same text, same id; ids index m_strings
    quint32 intern(QStringView s);
    QStringView view(Span s) const { return QStringView(m_text).sliced(s.offset, s.size); }
    QStringView string(quint32 id) const { return view(m_strings[id]); }

    QString m_text;
    std::vector<Span> m_strings;
    std::vector<Rule> m_rules;
    std::vector<quint32> m_ruleDomains; // string ids
    QList<QRegularExpression> m_regexes;

    RuleSet m_block;
    RuleSet m_allow;
    RuleSet m_document;
    RuleSet m_popup;
    RuleSet m_popupAllow;
    RuleSet m_elemHide;
    RuleSet m_genericHide;

    std::vector<quint32> m_generic;       // selector ids, sorted after finalize()
    std::vector<Entry> m_siteSelectors;   // domain hash -> selector id
    std::vector<Entry> m_siteExceptions;  // domain hash -> selector id
    int m_cosmeticCount = 0;

    // parse-only; emptied by finalize()
    QHash<quint64, quint32> m_intern;
    QSet<quint32> m_genericIds;
    bool m_finalized = false;
};
