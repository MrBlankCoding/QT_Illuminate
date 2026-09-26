find_package(Qt6 REQUIRED COMPONENTS QuickTest Widgets)

qt_add_executable(tst_qmltests main.cpp)

target_compile_definitions(tst_qmltests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(tst_qmltests PRIVATE
    Qt6::Gui
    Qt6::Widgets
    Qt6::QuickTest
    Qt6::WebEngineQuick
    Qt6::WebEngineCore
    QT_Illuminatemodule
    QT_Illuminatemoduleplugin
)

add_test(NAME tst_qmltests COMMAND tst_qmltests)

find_package(Qt6 REQUIRED COMPONENTS Test)

qt_add_executable(tst_colorextractor tst_ColorExtractor.cpp)
target_link_libraries(tst_colorextractor PRIVATE Qt6::Test QT_Illuminatemodule)
add_test(NAME tst_colorextractor COMMAND tst_colorextractor)

qt_add_executable(tst_permissionhandler tst_PermissionHandler.cpp)
target_link_libraries(tst_permissionhandler PRIVATE Qt6::Test QT_Illuminatemodule Qt6::WebEngineCore)
add_test(NAME tst_permissionhandler COMMAND tst_permissionhandler)
