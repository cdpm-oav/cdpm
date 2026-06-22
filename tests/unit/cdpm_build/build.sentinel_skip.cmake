# Test: build.sentinel_skip
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# An existing .cdpm_installed sentinel makes cdpm_build_dependency a no-op
# (no fetch, no driver dispatch) -- the run must not fail despite empty meta.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/sentinel_skip")
file(REMOVE_RECURSE "${tmp}")

set(CDPM_STORE_DIR "${tmp}/store")
set(CMAKE_BINARY_DIR "${tmp}/bin")

set(install_dir "${CDPM_STORE_DIR}/demo/abc123")
file(MAKE_DIRECTORY "${install_dir}")
file(TOUCH "${install_dir}/.cdpm_installed")

# Empty meta would explode in prepare_source; reaching it means skip failed.
cdpm_build_dependency("demo" "1.0.0" "abc123" "{}")

# If we got here without a fatal error, the skip path worked.
file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm_build_dependency skips when the sentinel exists")
