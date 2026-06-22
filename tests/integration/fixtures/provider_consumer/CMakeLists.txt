cmake_minimum_required(VERSION 3.25)

# The cdpm provider is injected via CMAKE_PROJECT_TOP_LEVEL_INCLUDES (set by the test driver),
# so it is registered before the first project() / find_package() call.
project(provider_consumer LANGUAGES CXX)

find_package(greet REQUIRED CONFIG)

if(NOT TARGET greet::greet)
    message(FATAL_ERROR "FAIL: greet::greet target is not available after find_package")
endif()

message(STATUS "PASS: find_package(greet) resolved via cdpm provider")
