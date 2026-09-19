cmake_minimum_required(VERSION 3.16)
project(QT_Illuminate LANGUAGES CXX)

if(APPLE)
    enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 WebEngineQuick)
find_package(Qt6 QUIET COMPONENTS QuickEffects)
if(Qt6QuickEffects_FOUND)
    set(QUICK_EFFECTS_LIB Qt6::QuickEffects)
else()
    find_package(Qt6QuickEffectsPrivate REQUIRED)
    set(QUICK_EFFECTS_LIB Qt6::QuickEffectsPrivate)
endif()

# ── C++ sources ───────────────────────────────────────────────────────────────
qt_add_executable(QT_Illuminate
    src/main.cpp

    src/core/BrowserTab.h
    src/core/BrowserTab.cpp

    src/core/TabModel.h
    src/core/TabModel.cpp

    src/core/BrowserController.h
    src/core/BrowserController.cpp

    src/core/BookmarkModel.h
    src/core/BookmarkModel.cpp

    src/utils/UrlResolver.h
    src/utils/UrlResolver.cpp

    src/utils/BrowserLogger.h
    src/utils/BrowserLogger.cpp

    src/utils/LogBridge.h

    src/utils/WindowRounding.h
)

if(APPLE)
    target_sources(QT_Illuminate PRIVATE src/utils/WindowRounding_mac.mm)
    target_link_libraries(QT_Illuminate PRIVATE "-framework Cocoa")
endif()

target_include_directories(QT_Illuminate PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
)

target_link_libraries(QT_Illuminate PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    ${QUICK_EFFECTS_LIB}
    Qt6::QuickControls2
    Qt6::WebEngineQuick
)

set_source_files_properties(ui/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set(QT_ILLUMINATE_QML_OUT_DIR "")
if(NOT APPLE)
    set(QT_ILLUMINATE_QML_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml")
endif()

qt_add_qml_module(QT_Illuminate
    URI             QT_Illuminate.ui
    VERSION         1.0
    RESOURCE_PREFIX /
    OUTPUT_DIRECTORY "${QT_ILLUMINATE_QML_OUT_DIR}"
    QML_FILES
        ui/BrowserWindow.qml
        ui/KeyboardShortcuts.qml
        ui/FindBar.qml
        ui/ZoomIndicator.qml
        ui/DownloadsPanel.qml
        ui/TabBar.qml
        ui/TabItem.qml
        ui/Toolbar.qml
        ui/Theme.qml
        ui/LucideIcon.qml
        ui/NewTabPage.qml
        ui/WindowControls.qml
        ui/SysButton.qml
    RESOURCES
        ui/icons/alert-triangle.svg
        ui/icons/globe.svg
        ui/icons/lock.svg
        ui/icons/plus.svg
        ui/icons/rotate-cw.svg
        ui/icons/x.svg
        ui/icons/minus.svg
        ui/icons/square.svg
        ui/icons/chevron-left.svg
        ui/icons/chevron-right.svg
        ui/icons/more-vertical.svg
        ui/icons/download.svg
        ui/icons/folder.svg
        ui/icons/star.svg
        ui/icons/star-filled.svg
)

# macos
set_target_properties(QT_Illuminate PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "QT_Illuminate"
)

# windows
if(WIN32)
    set_target_properties(QT_Illuminate PROPERTIES
        WIN32_EXECUTABLE TRUE
    )
    target_sources(QT_Illuminate PRIVATE
        packaging/windows/app.rc
    )
endif()


if(UNIX AND NOT APPLE)
    install(TARGETS QT_Illuminate RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
    install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/qml/"
            DESTINATION "${CMAKE_INSTALL_BINDIR}/qml")
    install(FILES packaging/qt-illuminate.desktop
            DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
    install(FILES packaging/icons/qt-illuminate.svg
            DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps")
    install(FILES packaging/hicolor/index.theme
            DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor")
endif()
