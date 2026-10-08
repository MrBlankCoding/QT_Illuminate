find_package(Qt6 REQUIRED COMPONENTS QuickTest Widgets)

qt_add_executable(tst_qmltests main.cpp)

target_compile_definitions(tst_qmltests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(tst_qmltests PRIVATE
    Qt6::Gui
    Qt6::Widgets
    Qt6::QuickTest
    QT_Illuminatemodule
    QT_Illuminatemoduleplugin
)

add_test(NAME tst_qmltests COMMAND tst_qmltests)

find_package(Qt6 REQUIRED COMPONENTS Test)

qt_add_executable(tst_browsersettings tst_BrowserSettings.cpp)
target_link_libraries(tst_browsersettings PRIVATE Qt6::Test QT_Illuminatemodule)
add_test(NAME tst_browsersettings COMMAND tst_browsersettings)

qt_add_executable(tst_browsercontroller tst_BrowserController.cpp)
target_link_libraries(tst_browsercontroller PRIVATE Qt6::Test QT_Illuminatemodule)
add_test(NAME tst_browsercontroller COMMAND tst_browsercontroller)

qt_add_executable(tst_permissionhandler tst_PermissionHandler.cpp)
target_link_libraries(tst_permissionhandler PRIVATE Qt6::Test QT_Illuminatemodule)
add_test(NAME tst_permissionhandler COMMAND tst_permissionhandler)

qt_add_executable(tst_shortcutbridge tst_ShortcutBridge.cpp)
target_link_libraries(tst_shortcutbridge PRIVATE Qt6::Test Qt6::Quick QT_Illuminatemodule)
add_test(NAME tst_shortcutbridge COMMAND tst_shortcutbridge)

qt_add_executable(tst_shortcutregistry tst_ShortcutRegistry.cpp)
target_link_libraries(tst_shortcutregistry PRIVATE Qt6::Test Qt6::Gui QT_Illuminatemodule)
add_test(NAME tst_shortcutregistry COMMAND tst_shortcutregistry)

qt_add_executable(tst_tabmodel tst_TabModel.cpp)
target_link_libraries(tst_tabmodel PRIVATE Qt6::Test QT_Illuminatemodule)
add_test(NAME tst_tabmodel COMMAND tst_tabmodel)

qt_add_executable(tst_sidebarmodel tst_SidebarModel.cpp)
target_link_libraries(tst_sidebarmodel PRIVATE Qt6::Test QT_Illuminatemodule)
add_test(NAME tst_sidebarmodel COMMAND tst_sidebarmodel)

if(WIN32)
    add_custom_command(TARGET tst_shortcutregistry POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory
                "$<TARGET_FILE_DIR:tst_shortcutregistry>/platforms"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_FILE_DIR:Qt6::Core>/../plugins/platforms/qoffscreen.dll"
                "$<TARGET_FILE_DIR:tst_shortcutregistry>/platforms/"
        COMMENT "Staging the offscreen platform plugin for tst_shortcutregistry"
    )
endif()

if(APPLE AND CEF_FOUND)
    foreach(_test_target tst_qmltests tst_browsersettings tst_browsercontroller tst_permissionhandler tst_shortcutbridge tst_shortcutregistry tst_tabmodel tst_sidebarmodel)
        add_custom_command(TARGET ${_test_target} POST_BUILD
            COMMAND install_name_tool -change
                "@executable_path/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
                "${CEF_BINARY_DIR_RELEASE}/Chromium Embedded Framework.framework/Chromium Embedded Framework"
                "$<TARGET_FILE:${_test_target}>"
            COMMENT "Updating CEF library path for ${_test_target}"
        )
    endforeach()
endif()
