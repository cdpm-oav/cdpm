# Test: get_version.missing_file_fallback
# When the VERSION file does not exist the module emits a warning and falls
# back to "0.0.0-unknown" instead of failing.

set(__tmp_dir "${CMAKE_CURRENT_LIST_DIR}/_tmp/missing_file_fallback")
file(MAKE_DIRECTORY "${__tmp_dir}")
# Intentionally do NOT create the VERSION file; the path must not exist.
set(__tmp_version "${__tmp_dir}/VERSION_absent")

set(__CDPM_VERSION_FILE "${__tmp_version}")
include(cdpm_version)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_get_version(ver)
assert_eq("${ver}" "0.0.0-unknown" "missing file -> fallback value")

file(REMOVE_RECURSE "${__tmp_dir}")
message(STATUS "PASS: _cdpm_get_version falls back when VERSION file is missing")
