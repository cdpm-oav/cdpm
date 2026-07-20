# Test: prepare.freezes_allowlist
include(cdpm_toolchain)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# IDE-injected variables (built-in allow-list) and user-extended ones
# (CDPM_TOOLCHAIN_VARS) are frozen into the wrapper with their current values.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/tc_freeze")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(CMAKE_TOOLCHAIN_FILE "")
set(CMAKE_BINARY_DIR "${tmp}")

# Built-in allow-list var (as Android Studio would inject via -D).
set(ANDROID_ABI "arm64-v8a")
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
# User-extended allow-list var.
set(CDPM_TOOLCHAIN_VARS "MY_CUSTOM_VAR")
set(MY_CUSTOM_VAR "custom-value")
# A variable NOT in the allow-list must not leak into the wrapper.
set(SOME_UNRELATED_VAR "should-not-appear")

cdpm_prepare_toolchain("deadbeef" out)

file(READ "${out}" content)
assert_match("${content}" "set\\(ANDROID_ABI \"arm64-v8a\"" "built-in allow-list var is frozen")
assert_match("${content}" "set\\(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE \"ONLY\"" "root-path mode is frozen")
assert_match("${content}" "set\\(MY_CUSTOM_VAR \"custom-value\"" "user allow-list var is frozen")
if(content MATCHES "SOME_UNRELATED_VAR")
    message(FATAL_ERROR "FAIL: a non-allow-listed variable leaked into the wrapper")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: wrapper freezes allow-list variables (built-in + user)")
