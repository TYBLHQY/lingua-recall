cmake_minimum_required(VERSION 3.16)
project(lingua-recall VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}" CACHE PATH "Install prefix")

# ── Dependencies ──────────────────────────────────────────
find_package(Qt6 6.7 REQUIRED COMPONENTS Core Qml Gui Sql)

qt_policy(SET QTP0001 NEW)

# ── Static library: FSRS-6 engine (pure C++, no Qt deps) ──
add_library(fsrs_engine STATIC
    src/FsrsEngine.h
    src/FsrsEngine.cpp
)

target_include_directories(fsrs_engine PUBLIC
    ${CMAKE_SOURCE_DIR}/src
)

# ── Static library: ReviewDb (depends on fsrs_engine + QtSql) ─
# Needs -fPIC because it's linked into the QML shared library.
add_library(review_db STATIC
    src/ReviewDb.h
    src/ReviewDb.cpp
)
set_property(TARGET review_db PROPERTY POSITION_INDEPENDENT_CODE ON)

target_include_directories(review_db PUBLIC
    ${CMAKE_SOURCE_DIR}/src
)
target_link_libraries(review_db PUBLIC
    Qt6::Sql
    fsrs_engine
)

# ── QML module: LinguaRecallHelper ─────────────────────────
qt_add_qml_module(lingua_recall_helper
    URI             LinguaRecallHelper
    VERSION         0.2.0
    SOURCES
        src/RecallHelper.h
        src/RecallHelper.cpp
    OUTPUT_DIRECTORY "${CMAKE_INSTALL_PREFIX}/lib/qml/LinguaRecallHelper"
)

set_target_properties(lingua_recall_helperplugin PROPERTIES
    INSTALL_RPATH "$ORIGIN"
    BUILD_RPATH "$ORIGIN"
)

target_link_libraries(lingua_recall_helper PRIVATE
    Qt6::Gui
    review_db
)

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

# ── Unit tests ─────────────────────────────────────────────
option(BUILD_TESTING "Build unit tests" ON)
if(BUILD_TESTING)
    find_package(Qt6 6.7 REQUIRED COMPONENTS Test)

    # FSRS-6 algorithm unit tests
    add_executable(tst_FsrsEngine
        tests/tst_FsrsEngine.cpp
    )
    target_include_directories(tst_FsrsEngine PRIVATE
        ${CMAKE_SOURCE_DIR}/src
    )
    target_link_libraries(tst_FsrsEngine PRIVATE
        Qt6::Test
        fsrs_engine
    )
    add_test(NAME tst_FsrsEngine COMMAND tst_FsrsEngine)

    # ReviewDb integration tests (uses in-memory SQLite)
    add_executable(tst_ReviewDb
        tests/tst_ReviewDb.cpp
    )
    target_include_directories(tst_ReviewDb PRIVATE
        ${CMAKE_SOURCE_DIR}/src
    )
    target_link_libraries(tst_ReviewDb PRIVATE
        Qt6::Test
        review_db
    )
    add_test(NAME tst_ReviewDb COMMAND tst_ReviewDb)
endif()
