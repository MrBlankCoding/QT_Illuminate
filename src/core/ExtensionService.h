#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>
#include <QVariantMap>

class QNetworkAccessManager;
class QNetworkReply;

struct ExtensionItem {
    QString id;
    QString name;
    QString version;
    QString description;
    QString path;
    QString iconPath;
    QString popupPath;
    bool enabled = true;
    bool pinned = true;
};

class ExtensionService : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(bool isDownloading READ isDownloading NOTIFY downloadingChanged)
    Q_PROPERTY(QString downloadStatus READ downloadStatus NOTIFY downloadStatusChanged)

public:
    enum ExtensionRoles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        VersionRole,
        DescriptionRole,
        PathRole,
        IconPathRole,
        PopupPathRole,
        EnabledRole,
        PinnedRole
    };

    explicit ExtensionService(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool isDownloading() const { return m_downloading; }
    QString downloadStatus() const { return m_downloadStatus; }

    Q_INVOKABLE bool isInstalled(const QString &id) const;
    Q_INVOKABLE QString getInstalledIconPath(const QString &id) const;
    Q_INVOKABLE void toggleExtension(const QString &id);
    Q_INVOKABLE void togglePin(const QString &id);
    Q_INVOKABLE void uninstallExtension(const QString &id);
    Q_INVOKABLE void installFromZipUrl(const QString &id, const QString &name, const QString &url);
    Q_INVOKABLE QString getPopupUrl(const QString &id) const;

    void installToWebEngine();

signals:
    void countChanged();
    void downloadingChanged();
    void downloadStatusChanged();
    void extensionInstalled(const QString &id);
    void extensionUninstalled(const QString &id);

private:
    void loadFromDisk();
    void saveToDisk();
    bool extractZip(const QByteArray &zipData, const QString &destDir);
    bool parseManifest(const QString &dirPath, QString &name, QString &version, QString &description, QString &iconPath, QString &popupPath);

    QList<ExtensionItem> m_extensions;
    QString m_baseDir;
    QNetworkAccessManager *m_nam = nullptr;
    bool m_downloading = false;
    bool m_signalsConnected = false;
    QString m_downloadStatus;
};
