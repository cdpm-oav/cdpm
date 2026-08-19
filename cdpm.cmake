# `SET_DEPENDENCY_PROVIDER` is supported only with version 3.24+
cmake_minimum_required(VERSION 3.25)
include_guard(GLOBAL)

message(STATUS "[cdpm] Setup dependency magic")

# Global options & variables
option(CDPM_DISABLE "Disable cdpm provider")
option(CDPM_BYPASS "Bypass all `find_package` calls into cmake default implementation")
option(CDPM_ALLOW_SYSTEM_PACKAGES "Fall back to a system find_package when a package is absent from the registry")

include(CMakeDependentOption)

cmake_dependent_option(CDPM_GENERATE_CPS
  "Generate CPS package descriptors after successful install"
  ON "CMAKE_VERSION VERSION_GREATER_EQUAL 4.3" OFF
)

set(CDPM_CACHE_PATH "${CMAKE_BINARY_DIR}/.cdpm" CACHE PATH "cdpm cache root directory path")

# Add cdpm modules path as first path to find
list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/core")

include(cdpm_provide_dependency)

cmake_language(SET_DEPENDENCY_PROVIDER cdpm_provide_dependency
    SUPPORTED_METHODS 
        FIND_PACKAGE
)
