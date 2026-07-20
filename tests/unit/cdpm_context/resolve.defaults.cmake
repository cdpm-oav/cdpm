# Test: context defaults preserve library behavior.
cmake_policy(SET CMP0011 NEW)
cmake_policy(SET CMP0140 NEW)

include(cdpm_context)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/resolve_defaults")
set(CMAKE_SOURCE_DIR "${tmp}/source")
set(CMAKE_BINARY_DIR "${tmp}/build")
unset(CDPM_PROJECT_DIR)
unset(CDPM_RUNTIME_DIR)

_cdpm_resolve_project_dir(project_dir)
_cdpm_resolve_runtime_dir(runtime_dir)

assert_eq("${project_dir}" "${tmp}/source" "project default remains CMAKE_SOURCE_DIR")
assert_eq("${runtime_dir}" "${tmp}/build/.cdpm" "runtime default remains CMAKE_BINARY_DIR/.cdpm")
if(EXISTS "${tmp}/store/.runtime")
    message(FATAL_ERROR "FAIL: resolving library defaults created store runtime artifacts")
endif()

message(STATUS "PASS: context library defaults")
