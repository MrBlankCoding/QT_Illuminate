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

qt_add_executable(tst_colorextractor tst_ColorExtractor.cpp)
target_link_libraries(tst_colorextractor PRIVATE Qt6::Test QT_Illuminatemodule)
add_test(NAME tst_colorextractor COMMAND tst_colorextractor)

qt_add_executable(tst_permissionhandler tst_PermissionHandler.cpp)
target_link_libraries(tst_permissionhandler PRIVATE Qt6::Test QT_Illuminatemodule)
add_test(NAME tst_permissionhandler COMMAND tst_permissionhandler)

qt_add_executable(tst_shortcutbridge tst_ShortcutBridge.cpp)
target_link_libraries(tst_shortcutbridge PRIVATE Qt6::Test Qt6::Quick QT_Illuminatemodule)
add_test(NAME tst_shortcutbridge COMMAND tst_shortcutbridge)

qt_add_executable(tst_shortcutregistry tst_ShortcutRegistry.cpp)
target_link_libraries(tst_shortcutregistry PRIVATE Qt6::Test Qt6::Gui QT_Illuminatemodule)
add_test(NAME tst_shortcutregistry COMMAND tst_shortcutregistry)

if(APPLE AND CEF_FOUND)
    # Link tests against CEF framework directly from CEF release directory
    foreach(_test_target tst_qmltests tst_colorextractor tst_permissionhandler tst_shortcutbridge tst_shortcutregistry)
        add_custom_command(TARGET ${_test_target} POST_BUILD
            COMMAND install_name_tool -change
                "@executable_path/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"
                "${CEF_BINARY_DIR_RELEASE}/Chromium Embedded Framework.framework/Chromium Embedded Framework"
                "$<TARGET_FILE:${_test_target}>"
            COMMENT "Updating CEF library path for ${_test_target}"
        )
    endforeach()
endif()
