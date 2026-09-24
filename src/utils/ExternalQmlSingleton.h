#pragma once

#include <QJSEngine>
#include <QQmlEngine>
#include <QtLogging>

// handels things main owns
template <typename T>
class ExternalQmlSingleton
{
public:
    static void setQmlInstance(T *instance) { s_instance = instance; }

    // called by QML engine
    static T *create(QQmlEngine *, QJSEngine *)
    {
        if (!s_instance)
        {
            qWarning("%s used from QML before setQmlInstance() was called",
                     T::staticMetaObject.className());
            return nullptr;
        }
        // main() owns it; stop the engine from deleting it on teardown
        QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
        return s_instance;
    }

private:
    inline static T *s_instance = nullptr;
};
