#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QList>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QWebEngineExtensionInfo>

#include <functional>
#include <optional>

class QNetworkAccessManager;
class QQuickWebEngineProfile;
class QWebEngineExtensionManager;
class ExtensionSchemeHandler;
class ExtensionService : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool downloading READ downloading NOTIFY downloadingChanged)
    Q_PROPERTY(QString downloadStatus READ downloadStatus NOTIFY downloadStatusChanged)

public:
    enum Roles
    {
        IdRole = Qt::UserRole + 1,
        NameRole,
        VersionRole,
        DescriptionRole,
        PathRole,
        IconPathRole,
        PopupPathRole,
        EnabledRole,
        PinnedRole,
        AuthorRole,
        HomepageRole,
        PermissionsRole,
        HostPermissionsRole,
        UserScriptsRole,
        SizeRole,
        UserScriptsEnabledRole
    };

    explicit ExtensionService(QObject *parent = nullptr);

    int count() const { return int(m_extensions.size()); }
    bool downloading() const { return m_downloading; }
    QString downloadStatus() const { return m_downloadStatus; }

    // QAbstractListModel
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE bool isInstalled(const QString &id) const;
    Q_INVOKABLE QString getPopupUrl(const QString &id) const;

    Q_INVOKABLE QString getInstalledIconPath(const QString &id) const;

    // rewrite into our URL
    static QString rewriteExtensionUrl(const QString &url);

    Q_INVOKABLE void togglePin(const QString &id);
    Q_INVOKABLE void toggleExtension(const QString &id);
    Q_INVOKABLE void uninstallExtension(const QString &id);
    Q_INVOKABLE void setUserScriptsEnabled(const QString &id, bool enabled);

    // call once after profile is ready
    Q_INVOKABLE void installToWebEngine();
    Q_INVOKABLE void installFromCrxUrl(const QString &extensionId, const QString &name, const QString &prodVersion = QString());

signals:
    void countChanged();
    void downloadingChanged();
    void downloadStatusChanged();

private slots:
    void onLoadFinished(const QWebEngineExtensionInfo &ext);
    void onUnloadFinished(const QWebEngineExtensionInfo &ext);

private:
    struct ExtensionItem
    {
        QString id; // app-level id (also the directory name under m_baseDir)
        QString name;
        QString version;
        QString description;
        QString path; // directory containing manifest.json
        QString iconPath;
        QString popupPath; // absolute path of the popup html (only used to derive the relative path)
        QString author;
        QString homepageUrl;
        QStringList permissions;      // humanized
        QStringList hostPermissions;
        bool hasUserScripts = false;
        bool userScriptsEnabled = false;
        qint64 sizeBytes = 0;
        bool enabled = true;
        bool pinned = true;
    };

    struct ManifestInfo
    {
        QString name;
        QString version = QStringLiteral("1.0");
        QString description;
        QString author;
        QString homepageUrl;
        QStringList permissions;
        QStringList hostPermissions;
        bool hasUserScripts = false;
        QString iconRel;
        QString popupRel;
        int manifestVersion = 0;
    };

    // profile and manager
    QQuickWebEngineProfile *profile() const;
    QWebEngineExtensionManager *extensionManager() const;
    QWebEngineExtensionManager *ensureManager(); // also wires up signals once per manager

    // lookup
    int indexOfId(const QString &id) const;
    int indexOfPath(const QString &path) const;
    std::optional<QWebEngineExtensionInfo> findEngineInfo(const ExtensionItem &item) const;
    QString buildPageUrl(const ExtensionItem &item, const QString &relativePath) const;

    // Engine state synchronisation
    void syncItemWithEngine(int row, const QWebEngineExtensionInfo &info);
    void confirmEnabled(const QString &id, int attemptsLeft);
    void deletePending(const QString &normalizedPath);

    // scheme handler
    void installSchemeHandler();
    QString directoryForEngineId(const QString &engineId) const;

    // install pipeline
    void extractZipAsync(const QByteArray &zipData, const QString &destDir, std::function<void(bool)> done);
    void completeInstall(const QString &id, const QString &fallbackName, const QString &stagingDir);
    void finishInstall(bool ok, const QString &status);
    void setDownloading(bool downloading);
    void setDownloadStatus(const QString &status);

    // paths
    QString rootDirFor(const QString &id) const;
    QString stagingRoot() const;
    void removeExtensionDir(const QString &dir) const;

    static bool locateManifestDir(const QString &root, QString *relDir);
    static bool parseManifest(const QString &dirPath, ManifestInfo &out);

    // persistence
    void loadFromDisk();
    void saveToDisk();

    QList<ExtensionItem> m_extensions;
    QString m_baseDir;
    QNetworkAccessManager *m_nam = nullptr;
    QPointer<QWebEngineExtensionManager> m_connectedManager;
    ExtensionSchemeHandler *m_schemeHandler = nullptr;
    QHash<QString, QString> m_pendingDeletions; // normalized extension path -> directory to delete
    bool m_downloading = false;
    QString m_downloadStatus;
};