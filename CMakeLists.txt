cmake_minimum_required(VERSION 3.16)
project(QT_Illuminate LANGUAGES CXX)

if(APPLE)
    enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickEffects QuickControls2 WebEngineQuick)

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
    Qt6::QuickEffects
    Qt6::QuickControls2
    Qt6::WebEngineQuick
)

set_source_files_properties(ui/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(QT_Illuminate
    URI             QT_Illuminate.ui
    VERSION         1.0
    RESOURCE_PREFIX /
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
