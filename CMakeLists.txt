cmake_minimum_required(VERSION 3.16)
project(QT_Illuminate VERSION 1.0.0 LANGUAGES CXX)

if(APPLE)
    enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(GNUInstallDirs)
include(CTest)

find_package(Qt6 REQUIRED COMPONENTS
    Core Gui Network Qml Quick QuickControls2 Concurrent
    WebEngineQuick WebEngineCore WebChannel WebChannelQuick
)

set(QT_NO_PRIVATE_MODULE_WARNING ON)
find_package(Qt6 REQUIRED COMPONENTS WebEngineCorePrivate WebEngineQuickPrivate)

qt_standard_project_setup()
qt_policy(SET QTP0004 NEW)

find_package(Qt6 QUIET COMPONENTS QuickEffects)
if(Qt6QuickEffects_FOUND)
    set(QUICK_EFFECTS_LIB Qt6::QuickEffects)
else()
    find_package(Qt6QuickEffectsPrivate REQUIRED)
    set(QUICK_EFFECTS_LIB Qt6::QuickEffectsPrivate)
endif()
qt_add_executable(QT_Illuminate
    src/main.cpp
)

target_include_directories(QT_Illuminate PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_link_libraries(QT_Illuminate PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::WebEngineQuick
    Qt6::WebEngineCore
    QT_Illuminatemodule
    QT_Illuminatemoduleplugin
)

set_target_properties(QT_Illuminate PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "QT_Illuminate"
    MACOSX_BUNDLE_GUI_IDENTIFIER "local.qt-illuminate.QT_Illuminate"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    # For camera/mic/screen-capture usage strings, point this at a custom plist:
    # MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/packaging/Info.plist.in"
)

set_source_files_properties(ui/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_library(QT_Illuminatemodule STATIC
    src/core/AdBlockEngine.h
    src/core/AdBlockEngine.cpp
    src/core/AdBlocker.h
    src/core/AdBlocker.cpp
    src/core/BrowserTab.h
    src/core/BrowserTab.cpp
    src/core/TabModel.h
    src/core/TabModel.cpp
    src/core/BrowserController.h
    src/core/BrowserController.cpp
    src/core/BookmarkModel.h
    src/core/BookmarkModel.cpp
    src/core/InternalPageManager.h
    src/core/InternalPageManager.cpp
    src/core/Profile.h
    src/core/Profile.cpp
    src/core/ProfileManager.h
    src/core/ProfileManager.cpp

    src/utils/UrlResolver.h
    src/utils/UrlResolver.cpp
    src/utils/BrowserLogger.h
    src/utils/BrowserLogger.cpp
    src/utils/ColorExtractor.h
    src/utils/ColorExtractor.cpp
    src/utils/ExternalQmlSingleton.h
    src/utils/LogBridge.h
    src/utils/PointerLockPermission.h
    src/utils/PointerLockPermission.cpp
    src/utils/WebVersion.h
    src/utils/WindowRounding.h
    src/utils/WindowHelper.h
    src/utils/WindowHelper.cpp
)

if(APPLE)
    target_sources(QT_Illuminatemodule PRIVATE src/utils/WindowRounding_mac.mm)
    target_link_libraries(QT_Illuminatemodule PRIVATE "-framework Cocoa")
endif()

if(WIN32)
    target_link_libraries(QT_Illuminatemodule PRIVATE dwmapi)
endif()

target_include_directories(QT_Illuminatemodule PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/utils
)

target_link_libraries(QT_Illuminatemodule PUBLIC
    Qt6::Core
    Qt6::Concurrent
    Qt6::Gui
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::WebEngineQuick
    Qt6::WebEngineCore
    Qt6::WebChannel
    Qt6::WebChannelQuick
    ${QUICK_EFFECTS_LIB}
PRIVATE
    Qt6::WebEngineCorePrivate
    Qt6::WebEngineQuickPrivate
)

qt_add_qml_module(QT_Illuminatemodule
    URI QT_Illuminate.ui
    VERSION 1.0
    RESOURCE_PREFIX /
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/qml/QT_Illuminate/ui"
    DEPENDENCIES QtWebEngine
    QML_FILES
        ui/Theme.qml
        ui/pages/BrowserWindow.qml
        ui/pages/NewTabPage.qml
        ui/pages/ProfilePicker.qml
        ui/pages/SettingsWindow.qml
        ui/components/ContextMenu.qml
        ui/components/DownloadsPanel.qml
        ui/components/FindBar.qml
        ui/components/KeyboardShortcuts.qml
        ui/components/LucideIcon.qml
        ui/components/PillButton.qml
        ui/components/ProfileTile.qml
        ui/components/ResizeGrips.qml
        ui/components/SuggestionBox.qml
        ui/components/TabBar.qml
        ui/components/TabItem.qml
        ui/components/Toolbar.qml
        ui/components/WindowControls.qml
        ui/components/ZoomIndicator.qml
    RESOURCES
        ui/icons/alert-triangle.svg
        ui/icons/chevron-left.svg
        ui/icons/chevron-right.svg
        ui/icons/download.svg
        ui/icons/folder.svg
        ui/icons/globe.svg
        ui/icons/image.svg
        ui/icons/lock.svg
        ui/icons/minus.svg
        ui/icons/more-vertical.svg
        ui/icons/pin.svg
        ui/icons/plus.svg
        ui/icons/rotate-cw.svg
        ui/icons/square.svg
        ui/icons/star-filled.svg
        ui/icons/star.svg
        ui/icons/x.svg
)

install(TARGETS QT_Illuminate
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

if(UNIX AND NOT APPLE)
    install(FILES packaging/qt-illuminate.desktop
            DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
    install(FILES packaging/icons/qt-illuminate.svg
            DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps")
    install(FILES packaging/hicolor/index.theme
            DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor")
else()
    qt_generate_deploy_qml_app_script(
        TARGET QT_Illuminate
        OUTPUT_SCRIPT QT_ILLUMINATE_DEPLOY_SCRIPT
        NO_UNSUPPORTED_PLATFORM_ERROR
    )
    install(SCRIPT ${QT_ILLUMINATE_DEPLOY_SCRIPT})
endif()

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()