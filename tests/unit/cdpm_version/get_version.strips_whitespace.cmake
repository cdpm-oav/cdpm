# Test: get_version.strips_whitespace
# Leading/trailing whitespace and blank lines are stripped from the read content.

set(__tmp_dir "${CMAKE_CURRENT_LIST_DIR}/_tmp/strips_whitespace")
file(MAKE_DIRECTORY "${__tmp_dir}")
set(__tmp_version "${__tmp_dir}/VERSION")
file(WRITE "${__tmp_version}" "  2.4.6  \n\n")

set(__CDPM_VERSION_FILE "${__tmp_version}")
include(cdpm_version)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_get_version(ver)
assert_eq("${ver}" "2.4.6" "surrounding whitespace stripped")

file(REMOVE_RECURSE "${__tmp_dir}")
message(STATUS "PASS: _cdpm_get_version strips surrounding whitespace")
