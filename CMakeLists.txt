cmake_minimum_required(VERSION 3.16)
project(lingua-recall VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}" CACHE PATH "Install prefix")

# ── Qt6 QML module (RecallHelper — no KF6 needed) ──────────
find_package(Qt6 6.7 REQUIRED COMPONENTS Core Qml Gui)

qt_policy(SET QTP0001 NEW)

qt_add_qml_module(lingua_recall_helper
    URI             LinguaRecallHelper
    VERSION         0.1.0
    SOURCES
        src/RecallHelper.h
        src/RecallHelper.cpp
    OUTPUT_DIRECTORY "${CMAKE_INSTALL_PREFIX}/lib/qml/LinguaRecallHelper"
)

set_target_properties(lingua_recall_helperplugin PROPERTIES
    INSTALL_RPATH "$ORIGIN"
    BUILD_RPATH "$ORIGIN"
)

target_link_libraries(lingua_recall_helper PRIVATE Qt6::Gui)

target_include_directories(lingua_recall_helper PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)

install(TARGETS lingua_recall_helper
    LIBRARY DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/qml/LinguaRecallHelper
)

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/LinguaRecallHelper/qmldir"
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/qml/LinguaRecallHelper
)
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/LinguaRecallHelper/plugins.qmltypes"
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/qml/LinguaRecallHelper
    OPTIONAL
)
