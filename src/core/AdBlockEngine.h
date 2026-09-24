#pragma once

#include <QHash>
#include <QList>
#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QStringView>
#include <QWebEngineUrlRequestInfo>

// filter matcher
// similar to ad block +
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

    bool shouldBlock(const Request &request) const;
    bool isPageAllowed(const QString &pageUrl, const QString &pageHost) const;
    bool shouldBlockPopup(const QUrl &url, const QUrl &openerUrl) const;
    Cosmetic cosmeticFor(const QString &pageUrl, const QString &pageHost) const;
    const QStringList &genericSelectors() const { return m_genericSelectors; }

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

    struct Rule
    {
        QString pattern; 
        QRegularExpression regex;
        Anchor anchor = Anchor::None;
        bool anchorEnd = false;
        bool matchCase = false;
        qint8 thirdParty = -1; 
        quint32 types = AllTypes;
        QStringList includeDomains;
        QStringList excludeDomains;
    };

    struct RuleSet
    {
        QHash<QString, QList<int>> byHost;  
        QHash<QString, QList<int>> byToken; 
        QList<int> generic;

        bool isEmpty() const { return byHost.isEmpty() && byToken.isEmpty() && generic.isEmpty(); }
    };

    void addRule(QStringView line);
    bool addCosmeticRule(QStringView line);
    void index(RuleSet &set, int ruleIndex);
    bool matchesSet(const RuleSet &set, const Request &request, bool checkOptions) const;
    bool matchesRule(const Rule &rule, const Request &request, bool checkOptions) const;
    bool matchesPattern(const Rule &rule, const Request &request) const;
    bool matchesPage(const RuleSet &set, const QString &pageUrl, const QString &pageHost) const;

    QList<Rule> m_rules;
    RuleSet m_block;
    RuleSet m_allow;      
    RuleSet m_document;
    RuleSet m_popup;
    RuleSet m_popupAllow;
    RuleSet m_elemHide;
    RuleSet m_genericHide;

    QStringList m_genericSelectors;
    QSet<QString> m_genericSet;
    QHash<QString, QStringList> m_siteSelectors;
    QHash<QString, QSet<QString>> m_siteExceptions;
    int m_cosmeticCount = 0;
};
