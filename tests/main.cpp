#include <QtQuickTest>
#include <QApplication>
#include <QDir>
#include <QObject>
#include <QTemporaryDir>
#include <QQmlEngine>

#include "BrowserController.h"
#include "Space.h"

class Setup : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;
    Space *m_space = nullptr;
    BrowserController *m_browser = nullptr;

public:
    ~Setup() override
    {
        BrowserController::setQmlInstance(nullptr);
        delete m_browser;
        m_browser = nullptr;
        delete m_space;
        m_space = nullptr;
    }

public slots:
    void applicationAvailable()
    {
        QCoreApplication::setOrganizationName("QT_Illuminate");
        QCoreApplication::setOrganizationDomain("qt-illuminate.local");
        QCoreApplication::setApplicationName("qmltests");

        m_space = new Space(QStringLiteral("qml-test-space"), QStringLiteral("QML Tests"),
                            QColor(QStringLiteral("#345678")), this);
        m_space->setStorageDir(m_dir.filePath(QStringLiteral("space")));
        QDir().mkpath(m_space->storageDir());
        m_browser = new BrowserController(m_space, this,
                                           m_dir.filePath(QStringLiteral("browser-settings.ini")));
        BrowserController::setQmlInstance(m_browser);
    }

    // the app's QML module is linked in statically; its qmldir lives at
    // qrc:/QT_Illuminate/ui, so tests can `import QT_Illuminate.ui`
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        engine->addImportPath(QStringLiteral("qrc:/"));
    }
};

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    Setup setup;
    return quick_test_main_with_setup(argc, argv, "qmltests",
                                      QUICK_TEST_SOURCE_DIR, &setup);
}

#include "main.moc"
