cmake_minimum_required(VERSION 3.25)
project(greet 
    VERSION 1.0.0
    LANGUAGES CXX
)

add_library(greet INTERFACE)
target_include_directories(greet
    INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)

include(GNUInstallDirs)
install(TARGETS greet EXPORT greetTargets)
install(DIRECTORY include/ DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
install(EXPORT greetTargets
    FILE greetConfig.cmake
    NAMESPACE greet::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/greet
)
