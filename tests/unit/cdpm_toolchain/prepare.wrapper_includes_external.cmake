# Test: prepare.wrapper_includes_external
include(cdpm_toolchain)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# When CMAKE_TOOLCHAIN_FILE is set, the generated wrapper include()s the real
# toolchain (so all its logic still applies) rather than replacing it.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/tc_wrapper")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(real "${tmp}/real-toolchain.cmake")
file(WRITE "${real}" "# real toolchain\n")

set(CMAKE_TOOLCHAIN_FILE "${real}")
set(CMAKE_BINARY_DIR "${tmp}/bin")

cdpm_prepare_toolchain("abc123" out)

set(expected "${tmp}/bin/.cdpm/toolchain/abc123.cmake")
assert_eq("${out}" "${expected}" "wrapper is generated under the binary dir")
if(NOT EXISTS "${expected}")
    message(FATAL_ERROR "FAIL: wrapper toolchain file was not written")
endif()

file(READ "${expected}" content)
assert_match("${content}" "include\\(\"${real}\"\\)" "wrapper includes the real toolchain")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: wrapper toolchain include()s the external toolchain")
