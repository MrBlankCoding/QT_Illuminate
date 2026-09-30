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
    QML_UNCREATABLE("CefProfile instances are managed by Profile")

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

    // Chromium's default for an embedder is to block third-party cookies. The
    // setting is stored as the profile-wide COOKIES content setting, so it
    // applies to every browser in this profile and survives restarts.
    bool thirdPartyCookiesAllowed() const;
    void setThirdPartyCookiesAllowed(bool allowed);

    // CefRequestContext.root_cache_path. Chromium profiles must be direct children of it.
    static QString rootCachePath();
    static QString cachePathForProfile(const QString &profileId);

    // drops every profile's CEF request context; required before CefShutdown
    static void releaseAllRequestContexts();

signals:
    void httpUserAgentChanged();
    void thirdPartyCookiesAllowedChanged();

private:
    // re-applies the policy; must run on the CEF UI thread
    void applyThirdPartyCookiePolicy();

    QString m_storagePath;
    QString m_cachePath;
    QString m_userAgent;
    CefRefPtr<CefRequestContext> m_requestContext;
    // remembered so a request context created later still gets the policy
    bool m_thirdPartyCookiesAllowed = true;
};
