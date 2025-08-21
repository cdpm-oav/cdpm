# `SET_DEPENDENCY_PROVIDER` is supported only with version 3.24+
cmake_minimum_required(VERSION 3.24)
include_guard(GLOBAL)


list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/core")

include(cdpm_provide_dependency)

cmake_language(SET_DEPENDENCY_PROVIDER cdpm_provide_dependency
    SUPPORTED_METHODS 
        FIND_PACKAGE
)
