# Test: get_version.from_file
# Verifies that _cdpm_get_version returns the content of an explicit VERSION file.

set(__tmp_dir "${CMAKE_CURRENT_LIST_DIR}/_tmp/from_file")
file(MAKE_DIRECTORY "${__tmp_dir}")
set(__tmp_version "${__tmp_dir}/VERSION")
file(WRITE "${__tmp_version}" "1.2.3\n")

set(__CDPM_VERSION_FILE "${__tmp_version}")
include(cdpm_version)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_get_version(ver)
assert_eq("${ver}" "1.2.3" "version read from explicit file")

file(REMOVE_RECURSE "${__tmp_dir}")
message(STATUS "PASS: _cdpm_get_version reads from VERSION file")
