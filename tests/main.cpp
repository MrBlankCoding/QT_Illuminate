#include <QtQuickTest>
#include <QtWebEngineQuick>
#include <QApplication>
#include <QObject>
#include <QQmlEngine>

class Setup : public QObject
{
    Q_OBJECT
public slots:
    void applicationAvailable()
    {
        QCoreApplication::setOrganizationName("QT_Illuminate");
        QCoreApplication::setOrganizationDomain("qt-illuminate.local");
        QCoreApplication::setApplicationName("qmltests");
        QtWebEngineQuick::initialize();
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