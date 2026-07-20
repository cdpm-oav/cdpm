cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE DESTINATION PROJECT_DIR)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
        message(FATAL_ERROR "Usage: cmake -DSOURCE=<packages.json> -DDESTINATION=<output-dir> "
            "-DPROJECT_DIR=<schema1-asset-base> -P convert-registry-schema1-to-schema2.cmake")
    endif()
endforeach()

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH cdpm_root)
list(PREPEND CMAKE_MODULE_PATH "${cdpm_root}/core")
include(cdpm_registry_converter)

cdpm_convert_registry_schema1_to_schema2(
    SOURCE "${SOURCE}"
    DESTINATION "${DESTINATION}"
    PROJECT_DIR "${PROJECT_DIR}"
)
