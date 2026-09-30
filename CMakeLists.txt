cmake_minimum_required(VERSION 3.16)
project(QT_Illuminate VERSION 1.0.0 LANGUAGES CXX)

if(APPLE)
    if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
        set(CMAKE_OSX_DEPLOYMENT_TARGET "27.0")
    endif()
    set(QT_ILLUMINATE_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}")

    enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(GNUInstallDirs)
include(CTest)

find_package(Qt6 REQUIRED COMPONENTS
    Core Gui Network Qml Quick QuickControls2 Concurrent
    Widgets PrintSupport Pdf
)

include(FetchContent)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
FetchContent_Declare(
    QHotkey
    GIT_REPOSITORY https://github.com/Skycoder42/QHotkey.git
    GIT_TAG 1.5.0
    SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qhotkey-src"
)
FetchContent_MakeAvailable(QHotkey)
unset(CMAKE_POLICY_VERSION_MINIMUM)  # restore for the rest of our project
if(DEFINED ENV{CEF_ROOT})
    set(CEF_ROOT $ENV{CEF_ROOT})
elseif(DEFINED CEF_ROOT)
    # Accept -DCEF_ROOT=<path> from the command line
endif()

if(CEF_ROOT)
    list(APPEND CMAKE_MODULE_PATH "${CEF_ROOT}/cmake")
    set(CEF_DIR "${CEF_ROOT}")
    find_package(CEF REQUIRED)
    set(CEF_FOUND ON)

    if(APPLE)
        set(CMAKE_OSX_DEPLOYMENT_TARGET "${QT_ILLUMINATE_DEPLOYMENT_TARGET}")
        list(FILTER CEF_COMPILER_FLAGS EXCLUDE REGEX "^-mmacosx-version-min=")
    endif()
endif()

if(CEF_FOUND)
    add_subdirectory(${CEF_LIBCEF_DLL_WRAPPER_PATH} libcef_dll_wrapper)

    if(OS_MAC)
        set(_CEF_FW_PATH "${CEF_BINARY_DIR_RELEASE}/Chromium Embedded Framework.framework")
        add_library(cef::cef UNKNOWN IMPORTED)
        set_target_properties(cef::cef PROPERTIES
            IMPORTED_LOCATION "${_CEF_FW_PATH}/Chromium Embedded Framework"
            INTERFACE_INCLUDE_DIRECTORIES "${CEF_INCLUDE_PATH}"
        )
        set_property(TARGET cef::cef APPEND PROPERTY
            INTERFACE_LINK_OPTIONS "-F${CEF_BINARY_DIR_RELEASE}")
        list(APPEND CEF_FRAMEWORK_LIBS "Chromium Embedded Framework")
    else()
        # Linux: libcef.so (or .a depending on CEF_LIBTYPE)
        ADD_LOGICAL_TARGET(libcef "${CEF_LIB_DEBUG}" "${CEF_LIB_RELEASE}")
        add_library(cef::cef ALIAS libcef)
    endif()

    # On macOS, the framework will be copied into the app bundle by the
    # POST_BUILD custom command on QT_Illuminate below.
endif()

qt_standard_project_setup()
qt_policy(SET QTP0004 NEW)

qt_add_executable(QT_Illuminate
    src/main.cpp
)

target_include_directories(QT_Illuminate PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(QT_Illuminate PRIVATE QT_ILLUMINATE_VERSION="${PROJECT_VERSION}")

target_link_libraries(QT_Illuminate PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::Widgets
    QT_Illuminatemodule
    QT_Illuminatemoduleplugin
)

if(TARGET cef::cef)
    target_link_libraries(QT_Illuminate PRIVATE cef::cef libcef_dll_wrapper)
endif()

if(OS_MAC AND CEF_FOUND)
    set_target_properties(QT_Illuminate PROPERTIES
        BUILD_RPATH "@executable_path/../Frameworks"
        INSTALL_RPATH "@executable_path/../Frameworks"
    )
    # Copy the CEF framework into the bundle at build time with proper macOS
    # framework structure (Versions/A symlinks) as expected by CEF's runtime.
    add_custom_command(TARGET QT_Illuminate POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CEF_BINARY_DIR_RELEASE}/Chromium Embedded Framework.framework"
            "$<TARGET_FILE_DIR:QT_Illuminate>/../Frameworks/Chromium Embedded Framework.framework/Versions/A"
        COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:QT_Illuminate>/../Frameworks/Chromium Embedded Framework.framework/Versions"
        COMMAND ln -sf "A" "$<TARGET_FILE_DIR:QT_Illuminate>/../Frameworks/Chromium Embedded Framework.framework/Versions/Current"
        COMMAND ln -sf "Versions/A/Chromium Embedded Framework" "$<TARGET_FILE_DIR:QT_Illuminate>/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
        COMMAND ln -sf "Versions/A/Libraries" "$<TARGET_FILE_DIR:QT_Illuminate>/../Frameworks/Chromium Embedded Framework.framework/Libraries"
        COMMAND ln -sf "Versions/A/Resources" "$<TARGET_FILE_DIR:QT_Illuminate>/../Frameworks/Chromium Embedded Framework.framework/Resources"
        COMMAND ln -sf "Versions/A/Info.plist" "$<TARGET_FILE_DIR:QT_Illuminate>/../Frameworks/Chromium Embedded Framework.framework/Info.plist"
        COMMENT "Copying Chromium Embedded Framework.framework into the bundle with proper structure"
    )

    foreach(_suffix_list ${CEF_HELPER_APP_SUFFIXES})
        string(REPLACE ":" ";" _suffix_list ${_suffix_list})
        list(GET _suffix_list 0 _name_suffix)
        list(GET _suffix_list 1 _target_suffix)
        list(GET _suffix_list 2 _plist_suffix)

        set(_helper_target "QT_Illuminate_Helper${_target_suffix}")
        set(_helper_output_name "QT_Illuminate Helper${_name_suffix}")

        set(_helper_info_plist "${CMAKE_CURRENT_BINARY_DIR}/helper-Info${_target_suffix}.plist")
        file(READ "${CMAKE_CURRENT_SOURCE_DIR}/packaging/helper-Info.plist.in" _plist_contents)
        string(REPLACE "\${EXECUTABLE_NAME}" "${_helper_output_name}" _plist_contents "${_plist_contents}")
        string(REPLACE "\${BUNDLE_ID_SUFFIX}" "${_plist_suffix}" _plist_contents "${_plist_contents}")
        string(REPLACE "\${VERSION}" "${PROJECT_VERSION}" _plist_contents "${_plist_contents}")
        file(WRITE "${_helper_info_plist}" "${_plist_contents}")

        add_executable(${_helper_target} MACOSX_BUNDLE src/cef_helper/process_helper_mac.cpp)
        target_include_directories(${_helper_target} PRIVATE "${CEF_INCLUDE_PATH}")
        target_link_libraries(${_helper_target} PRIVATE cef::cef libcef_dll_wrapper "-framework Cocoa")
        set_target_properties(${_helper_target} PROPERTIES
            AUTOMOC OFF
            OUTPUT_NAME "${_helper_output_name}"
            MACOSX_BUNDLE_INFO_PLIST "${_helper_info_plist}"
        )

        add_dependencies(QT_Illuminate ${_helper_target})
        set(_helper_staged "$<TARGET_FILE_DIR:QT_Illuminate>/../Frameworks/${_helper_output_name}.app")
        add_custom_command(TARGET QT_Illuminate POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E rm -rf "${_helper_staged}"
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                "$<TARGET_BUNDLE_DIR:${_helper_target}>"
                "${_helper_staged}"
            COMMENT "Copying ${_helper_output_name}.app into the bundle"
            VERBATIM
        )

        add_custom_command(TARGET QT_Illuminate POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_helper_staged}/Contents/Frameworks"
            COMMAND ${CMAKE_COMMAND} -E rm -rf "${_helper_staged}/Contents/Frameworks/Chromium Embedded Framework.framework"
            COMMAND ${CMAKE_COMMAND} -E create_symlink
                "../../../Chromium Embedded Framework.framework"
                "${_helper_staged}/Contents/Frameworks/Chromium Embedded Framework.framework"
            COMMENT "Symlinking Chromium Embedded Framework.framework into ${_helper_output_name}.app"
            VERBATIM
        )
    endforeach()
endif()

set_target_properties(QT_Illuminate PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "QT_Illuminate"
    MACOSX_BUNDLE_GUI_IDENTIFIER "local.qt-illuminate.QT_Illuminate"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_ICON_FILE "AppIcon"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/packaging/Info.plist.in"
)

if(APPLE)
    set(APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/packaging/icons/AppIcon.icns")
    if(NOT EXISTS "${APP_ICON}")
        message(FATAL_ERROR "Missing app icon: ${APP_ICON}")
    endif()
    add_custom_command(TARGET QT_Illuminate POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${APP_ICON}"
                "$<TARGET_BUNDLE_DIR:QT_Illuminate>/Contents/Resources/AppIcon.icns"
        COMMENT "Installing AppIcon.icns into the bundle"
    )
endif()

set_source_files_properties(ui/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_library(QT_Illuminatemodule STATIC
    # --- core/browser: top-level browser orchestration ---
    src/core/browser/BrowserTab.h
    src/core/browser/BrowserTab.cpp
    src/core/browser/BrowserSettings.h
    src/core/browser/BrowserSettings.cpp
    src/core/browser/BrowserController.h
    src/core/browser/BrowserController.cpp
    src/core/browser/InternalPageManager.h
    src/core/browser/InternalPageManager.cpp

    # --- core/models: Qt models exposed to QML ---
    src/core/models/TabModel.h
    src/core/models/TabModel.cpp
    src/core/models/BookmarkModel.h
    src/core/models/BookmarkModel.cpp

    # --- core/profiles ---
    src/core/profiles/Profile.h
    src/core/profiles/Profile.cpp
    src/core/profiles/ProfileManager.h
    src/core/profiles/ProfileManager.cpp

    # --- core/menus: native menu bar and keyboard shortcuts ---
    src/core/menus/MenuItem.h
    src/core/menus/MenuItem.cpp
    src/core/menus/AppMenu.h
    src/core/menus/AppMenu.cpp
    src/core/menus/NativeMenuBar.h
    src/core/menus/NativeMenuBar.cpp
    src/core/menus/ShortcutRegistry.h
    src/core/menus/ShortcutRegistry.cpp

    # --- core/system: diagnostics and permission prompts ---
    src/core/system/SystemInfo.h
    src/core/system/SystemInfo.cpp
    src/core/system/MemoryMonitor.h
    src/core/system/MemoryMonitor.cpp
    src/core/system/PermissionHandler.h
    src/core/system/PermissionHandler.cpp

    # --- core/cef: Chromium Embedded Framework integration ---
    src/core/cef/CefManager.h
    src/core/cef/CefManager.cpp
    src/core/cef/CefBrowserWrapper.h
    src/core/cef/CefBrowserWrapper.cpp
    src/core/cef/CefTabClient.h
    src/core/cef/CefTabClient.cpp
    src/core/cef/CefQuickItem.h
    src/core/cef/CefQuickItem.cpp
    src/core/cef/CefProfile.h
    src/core/cef/CefProfile.cpp
    src/core/cef/CefDownloadWrapper.h
    src/core/cef/CefDownloadWrapper.cpp
    src/core/cef/CefMainBrowserId.h
    src/core/cef/CefLoadHandler.h
    src/core/cef/CefLoadHandler.cpp
    src/core/cef/CefDisplayHandler.h
    src/core/cef/CefDisplayHandler.cpp
    src/core/cef/CefContextMenuHandler.h
    src/core/cef/CefContextMenuHandler.cpp
    src/core/cef/CefDownloadHandler.h
    src/core/cef/CefDownloadHandler.cpp
    src/core/cef/CefFindHandler.h
    src/core/cef/CefFindHandler.cpp
    src/core/cef/CefPermissionHandler.h
    src/core/cef/CefPermissionHandler.cpp
    src/core/cef/CefRequestHandler.h
    src/core/cef/CefRequestHandler.cpp

    src/utils/cef_helpers.h
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
    src/utils/PointerLockEmulation.h
    src/utils/PrintHelper.h
    src/utils/PrintHelper.cpp
    src/utils/ShortcutBridge.h
    src/utils/ShortcutBridge.cpp
    src/utils/WebVersion.h
    src/utils/WindowRounding.h
    src/utils/WindowHelper.h
    src/utils/WindowHelper.cpp
)

if(APPLE)
    target_sources(QT_Illuminatemodule PRIVATE src/utils/WindowRounding_mac.mm)
    target_sources(QT_Illuminatemodule PRIVATE src/utils/PointerLockEmulation.mm)
    target_sources(QT_Illuminatemodule PRIVATE src/core/system/PermissionHandler_mac.mm)
    target_sources(QT_Illuminatemodule PRIVATE src/core/cef/CefManager_mac.mm src/core/cef/CefBrowserWrapper_mac.mm)
    set_source_files_properties(src/utils/PointerLockEmulation.mm PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
    target_link_libraries(QT_Illuminatemodule PRIVATE
        "-framework Cocoa" "-framework AppKit" "-framework AVFoundation" "-framework CoreLocation" "-framework IOSurface")
else()
    # generic Qt event-filter/cursor-warp pointer lock for Linux and Windows
    target_sources(QT_Illuminatemodule PRIVATE src/utils/PointerLockEmulation.cpp)
endif()

if(WIN32)
    target_link_libraries(QT_Illuminatemodule PRIVATE dwmapi psapi)
endif()

target_include_directories(QT_Illuminatemodule PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core/browser
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core/cef
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core/menus
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core/models
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core/profiles
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core/system
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
    Qt6::Widgets
    Qt6::PrintSupport
    Qt6::Pdf
)

if(TARGET cef::cef)
    target_link_libraries(QT_Illuminatemodule PUBLIC cef::cef libcef_dll_wrapper)
endif()

# QHotkey handles global shortcuts without Qt private headers
target_link_libraries(QT_Illuminatemodule PRIVATE QHotkey::QHotkey)

qt_add_qml_module(QT_Illuminatemodule
    URI QT_Illuminate.ui
    VERSION 1.0
    RESOURCE_PREFIX /
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/qml/QT_Illuminate/ui"
    QML_FILES
        ui/Theme.qml
        ui/pages/BrowserWindow.qml
        ui/pages/MemoryPage.qml
        ui/pages/NewTabPage.qml
        ui/pages/ProfilePicker.qml
        ui/pages/SettingsWindow.qml
        ui/pages/SetupPage.qml
        ui/pages/settings/PrivacySettingsPage.qml
        ui/pages/settings/SearchSettingsPage.qml
        ui/pages/settings/ShortcutsSettingsPage.qml
        ui/pages/settings/StartupSettingsPage.qml
        ui/pages/settings/TabsSettingsPage.qml
        ui/components/LucideIcon.qml
        ui/components/PillButton.qml
        ui/components/chrome/ResizeGrips.qml
        ui/components/chrome/WindowControls.qml
        ui/components/chrome/WindowDragRegion.qml
        ui/components/browser/BookmarksBar.qml
        ui/components/browser/KeyboardShortcuts.qml
        ui/components/browser/PrintController.qml
        ui/components/browser/TabBar.qml
        ui/components/browser/TabItem.qml
        ui/components/browser/TabSlot.qml
        ui/components/browser/Toolbar.qml
        ui/components/overlays/AppMenuBar.qml
        ui/components/overlays/ContextMenu.qml
        ui/components/overlays/DownloadsPanel.qml
        ui/components/overlays/FindBar.qml
        ui/components/overlays/SuggestionBox.qml
        ui/components/overlays/ZoomIndicator.qml
        ui/components/profiles/ProfileEditor.qml
        ui/components/profiles/ProfileTile.qml
        ui/components/settings/Footnote.qml
        ui/components/settings/NavItem.qml
        ui/components/settings/SectionHeader.qml
        ui/components/settings/SettingCombo.qml
        ui/components/settings/SettingField.qml
        ui/components/settings/SettingItem.qml
        ui/components/settings/SettingsCard.qml
        ui/components/settings/SettingsPage.qml
        ui/components/settings/SettingSwitch.qml
        ui/components/settings/ShortcutField.qml
    RESOURCES
        ui/resources/js/pointer-lock-shim.js
        ui/resources/js/devtools-bridge.js
        ui/icons/alert-triangle.svg
        ui/icons/chevron-left.svg
        ui/icons/chevron-right.svg
        ui/icons/copy.svg
        ui/icons/download.svg
        ui/icons/folder.svg
        ui/icons/globe.svg
        ui/icons/image.svg
        ui/icons/lock.svg
        ui/icons/activity.svg
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