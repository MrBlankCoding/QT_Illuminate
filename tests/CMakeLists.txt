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