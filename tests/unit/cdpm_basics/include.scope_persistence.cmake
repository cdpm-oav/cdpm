# Test: constants survive when cdpm_basics is first included from a function scope.
cmake_policy(VERSION 3.25...4.0)

include("${CDPM_TEST_HELPERS}/helpers.cmake")

function(load_basics_in_function)
    include(cdpm_basics)
    assert_true("${__CDPM_ROOT}" "root is available inside the first include scope")
endfunction()

load_basics_in_function()

assert_true("${__CDPM_ROOT}" "root survives the first include function scope")
assert_true("${__CDPM_CORE_DIR}" "core dir survives the first include function scope")
assert_true("${__CDPM_TOOLCHAIN_VARS_BUILTIN}" "toolchain constants survive the first include function scope")
assert_eq("${__CDPM_TOOLCHAIN_SEMANTIC_NATIVE}" "native" "native sentinel survives the first include scope")

_cdpm_resolve_project_dir(project_dir)
assert_true("${project_dir}" "functions defined by a scoped include remain callable")

message(STATUS "PASS: cdpm_basics scoped include persistence")
