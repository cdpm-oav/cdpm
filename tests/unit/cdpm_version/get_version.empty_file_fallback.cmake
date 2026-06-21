# Test: get_version.empty_file_fallback
# An empty VERSION file triggers the same fallback path as a missing file.

set(__tmp_dir "${CMAKE_CURRENT_LIST_DIR}/_tmp/empty_file_fallback")
file(MAKE_DIRECTORY "${__tmp_dir}")
set(__tmp_version "${__tmp_dir}/VERSION")
file(WRITE "${__tmp_version}" "")

set(__CDPM_VERSION_FILE "${__tmp_version}")
include(cdpm_version)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_get_version(ver)
assert_eq("${ver}" "0.0.0-unknown" "empty file -> fallback value")

file(REMOVE_RECURSE "${__tmp_dir}")
message(STATUS "PASS: _cdpm_get_version falls back when VERSION file is empty")
