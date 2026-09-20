# Test: the toolchain freeze allow-list is owned by cdpm_basics and extended by CDPM_TOOLCHAIN_VARS.
cmake_policy(VERSION 3.25...4.0)

include(cdpm_basics)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

assert_true("${__CDPM_TOOLCHAIN_VARS_BUILTIN}" "built-in allow-list is defined")
assert_eq("${__CDPM_TOOLCHAIN_SEMANTIC_NATIVE}" "native" "native sentinel is the literal 'native'")

unset(CDPM_TOOLCHAIN_VARS)
_cdpm_toolchain_var_list(base_list)
list(FIND base_list "CMAKE_SYSTEM_NAME" idx_system)
assert_ne("${idx_system}" "-1" "allow-list contains a built-in system variable")
list(FIND base_list "CMAKE_C_COMPILER" idx_c)
assert_ne("${idx_c}" "-1" "allow-list always freezes per-language compilers")

set(CDPM_TOOLCHAIN_VARS "MY_CUSTOM_VAR")
_cdpm_toolchain_var_list(extended_list)
list(FIND extended_list "MY_CUSTOM_VAR" idx_custom)
assert_ne("${idx_custom}" "-1" "CDPM_TOOLCHAIN_VARS entries join the allow-list")

message(STATUS "PASS: cdpm_basics toolchain var list")
