# Test: cdpm_basics captures the cdpm root and core directory.
cmake_policy(VERSION 3.25...4.0)

include(cdpm_basics)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

assert_true("${__CDPM_CORE_DIR}" "__CDPM_CORE_DIR is set")
assert_true("${__CDPM_ROOT}" "__CDPM_ROOT is set")
assert_match("${__CDPM_CORE_DIR}" "/core$" "__CDPM_CORE_DIR points at the core directory")

cmake_path(GET __CDPM_CORE_DIR PARENT_PATH expected_root)
assert_eq("${__CDPM_ROOT}" "${expected_root}" "__CDPM_ROOT is the parent of the core directory")

if(NOT EXISTS "${__CDPM_ROOT}/cdpm.cmake")
    message(FATAL_ERROR "FAIL: __CDPM_ROOT does not contain cdpm.cmake: ${__CDPM_ROOT}")
endif()

message(STATUS "PASS: cdpm_basics root and core paths")
