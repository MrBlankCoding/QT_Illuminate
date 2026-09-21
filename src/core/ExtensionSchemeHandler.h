#pragma once

#include <QLatin1String>
#include <QString>
#include <QWebEngineUrlSchemeHandler>

#include <functional>

class QWebEngineUrlRequestJob;

// "illum-ext://<extension-id>/<path>"

class ExtensionSchemeHandler final : public QWebEngineUrlSchemeHandler
{
    Q_OBJECT
public:
    using Resolver = std::function<QString(const QString &host)>;

    static QLatin1String scheme() noexcept { return QLatin1String("illum-ext"); }

    explicit ExtensionSchemeHandler(Resolver resolver, QObject *parent = nullptr);

    void requestStarted(QWebEngineUrlRequestJob *job) override;

private:
    Resolver m_resolver;
    QByteArray m_chromeShimJs;
};