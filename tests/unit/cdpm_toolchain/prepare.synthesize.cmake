# Test: prepare.synthesize
include(cdpm_toolchain)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# With no CMAKE_TOOLCHAIN_FILE, the wrapper is generated under the binary dir,
# named by the config hash, freezing the current compiler/system allow-list vars.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/tc_synth")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(CMAKE_TOOLCHAIN_FILE "")
set(CMAKE_BINARY_DIR "${tmp}")
set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_CXX_COMPILER "/usr/bin/c++-cdpm-fake")

cdpm_prepare_toolchain("deadbeef" out)

set(expected "${tmp}/.cdpm/toolchain/deadbeef.cmake")
assert_eq("${out}" "${expected}" "synthesized toolchain path is hash-named under the binary dir")
if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "FAIL: synthesized toolchain file was not written")
endif()

file(READ "${expected}" content)
assert_match("${content}" "CMAKE_CXX_COMPILER" "synthesized toolchain records the compiler")
assert_match("${content}" "CMAKE_SYSTEM_NAME" "synthesized toolchain records the system name")

# Idempotent: a second call does not rewrite (sentinel by mtime).
file(TIMESTAMP "${expected}" ts1)
cdpm_prepare_toolchain("deadbeef" out2)
file(TIMESTAMP "${expected}" ts2)
assert_eq("${out2}" "${expected}" "second call returns the same path")
assert_eq("${ts1}" "${ts2}" "second call does not rewrite the existing toolchain")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm_prepare_toolchain synthesizes a minimal toolchain idempotently")
