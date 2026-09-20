# cdpm main injection point
cmake_minimum_required(VERSION 3.25...4.0)

include_guard(GLOBAL)

message(STATUS "[cdpm] Setup dependency magic")

# Add cdpm modules path as first path to find
cmake_path(SET __CDPM_CORE_MODULE_PATH SET "${CMAKE_CURRENT_LIST_DIR}/core")
if(NOT __CDPM_CORE_MODULE_PATH IN_LIST CMAKE_MODULE_PATH)
    list(PREPEND CMAKE_MODULE_PATH "${__CDPM_CORE_MODULE_PATH}")
endif()

include(cdpm_provide_dependency)

cmake_language(SET_DEPENDENCY_PROVIDER cdpm_provide_dependency
    SUPPORTED_METHODS 
        FIND_PACKAGE
)

# TODO: rewatch is this really required here
# Language canonicalization: ensure CMAKE_C_COMPILER and CMAKE_CXX_COMPILER are
# populated whenever cdpm is loaded inside a real project context, so the config hash
# sees a consistent language set across orchestrator, provider-injected child builds and
# direct includes after project(). check_language caches its result, so the probes are
# cheap on subsequent runs and harmless when a compiler is absent (the corresponding
# variable is simply left unset).
if(NOT CMAKE_SCRIPT_MODE_FILE
        AND DEFINED CMAKE_SOURCE_DIR
        AND NOT CMAKE_SOURCE_DIR STREQUAL "")
    include(CheckLanguage)
    if(NOT DEFINED CMAKE_C_COMPILER)
        check_language(C)
    endif()
    if(NOT DEFINED CMAKE_CXX_COMPILER)
        check_language(CXX)
    endif()
endif()
