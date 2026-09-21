cmake_minimum_required(VERSION 3.24)

project(SageChrona VERSION 2.0.0 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

add_library(timelogger_core
    Sources/GitTracker.cpp
    Sources/ReportFormatter.cpp
    Sources/TimeLog.cpp
)

target_include_directories(timelogger_core PUBLIC Sources)

# Some Command Line Tools installations keep libc++ headers inside the active
# SDK instead of the compiler directory. Add that location only when needed.
set(TIMLOGGER_HAS_CHRONO_HEADER OFF)
foreach(TIMLOGGER_INCLUDE_DIR IN LISTS CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES)
    if(EXISTS "${TIMLOGGER_INCLUDE_DIR}/chrono")
        set(TIMLOGGER_HAS_CHRONO_HEADER ON)
        break()
    endif()
endforeach()

if(APPLE AND NOT TIMLOGGER_HAS_CHRONO_HEADER)
    execute_process(
        COMMAND xcrun --show-sdk-path
        OUTPUT_VARIABLE TIMLOGGER_SDK_PATH
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(EXISTS "${TIMLOGGER_SDK_PATH}/usr/include/c++/v1/chrono")
        target_include_directories(timelogger_core SYSTEM PUBLIC
            "${TIMLOGGER_SDK_PATH}/usr/include/c++/v1"
        )
    endif()
endif()
target_compile_options(timelogger_core PRIVATE -Wall -Wextra -Wpedantic)

add_executable(SageChrona MACOSX_BUNDLE
    Sources/main.mm
)

target_link_libraries(SageChrona PRIVATE
    timelogger_core
    "-framework AppKit"
    "-framework Foundation"
)

target_compile_options(SageChrona PRIVATE -Wall -Wextra -Wpedantic)

set_target_properties(SageChrona PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "SageChrona"
    MACOSX_BUNDLE_GUI_IDENTIFIER "io.github.phcodesage.sagechrona"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Info.plist.in"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
)

if(APPLE)
    add_custom_command(TARGET SageChrona POST_BUILD
        COMMAND codesign --force --deep --sign - "$<TARGET_BUNDLE_DIR:SageChrona>"
        COMMENT "Applying an ad hoc signature to SageChrona.app"
        VERBATIM
    )
endif()

enable_testing()

add_executable(timelogger_core_tests
    Tests/TimeLogTests.cpp
)

target_link_libraries(timelogger_core_tests PRIVATE timelogger_core)
target_compile_options(timelogger_core_tests PRIVATE -Wall -Wextra -Wpedantic)
add_test(NAME timelogger_core_tests COMMAND timelogger_core_tests)

install(TARGETS SageChrona BUNDLE DESTINATION .)
