cmake_minimum_required(VERSION 3.25)

# The cdpm provider is injected via CMAKE_PROJECT_TOP_LEVEL_INCLUDES (set by the test driver).
project(fmt_consumer LANGUAGES CXX)

find_package(fmt REQUIRED)

if(NOT TARGET fmt::fmt)
    message(FATAL_ERROR "FAIL: fmt::fmt target is not available after find_package")
endif()

add_executable(use_fmt main.cpp)
target_link_libraries(use_fmt PRIVATE fmt::fmt)

message(STATUS "PASS: find_package(fmt) resolved via cdpm provider")
