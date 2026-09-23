#include <QtQuickTest>
#include <QtWebEngineQuick>
#include <QApplication>
#include <QObject>

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
};

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    Setup setup;
    return quick_test_main_with_setup(argc, argv, "qmltests",
                                      QUICK_TEST_SOURCE_DIR, &setup);
}

#include "main.moc"