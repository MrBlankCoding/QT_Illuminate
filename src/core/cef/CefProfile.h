#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>
#include <include/cef_request_context.h>
#include <include/cef_request_context_handler.h>

class CefProfile : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(CefProfile)
    QML_UNCREATABLE("Use Browser.webProfile")

    Q_PROPERTY(QString storagePath READ storagePath CONSTANT)
    Q_PROPERTY(QString cachePath READ cachePath CONSTANT)
    Q_PROPERTY(QString httpUserAgent READ httpUserAgent WRITE setHttpUserAgent NOTIFY httpUserAgentChanged)
    Q_PROPERTY(bool thirdPartyCookiesAllowed READ thirdPartyCookiesAllowed
                   WRITE setThirdPartyCookiesAllowed NOTIFY thirdPartyCookiesAllowedChanged)

public:
    explicit CefProfile(const QString &storagePath, const QString &cachePath, QObject *parent = nullptr);
    ~CefProfile() override;

    QString storagePath() const { return m_storagePath; }
    QString cachePath() const { return m_cachePath; }

    QString httpUserAgent() const { return m_userAgent; }
    void setHttpUserAgent(const QString &ua);

    CefRefPtr<CefRequestContext> requestContext();

    bool thirdPartyCookiesAllowed() const;
    void setThirdPartyCookiesAllowed(bool allowed);

    static QString rootCachePath();
    static CefProfile *instance();
    static QString storageDir();
    static void releaseAllRequestContexts();

signals:
    void httpUserAgentChanged();
    void thirdPartyCookiesAllowedChanged();

private:
    void applyThirdPartyCookiePolicy();

    QString m_storagePath;
    QString m_cachePath;
    QString m_userAgent;
    CefRefPtr<CefRequestContext> m_requestContext;
    bool m_thirdPartyCookiesAllowed = true;
};
