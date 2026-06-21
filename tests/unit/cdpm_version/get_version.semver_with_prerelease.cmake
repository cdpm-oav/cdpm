# Test: get_version.semver_with_prerelease
# Semver pre-release suffix (-alpha.1) is accepted without value mutation.

set(__tmp_dir "${CMAKE_CURRENT_LIST_DIR}/_tmp/semver_with_prerelease")
file(MAKE_DIRECTORY "${__tmp_dir}")
set(__tmp_version "${__tmp_dir}/VERSION")
file(WRITE "${__tmp_version}" "1.2.3-alpha.1\n")

set(__CDPM_VERSION_FILE "${__tmp_version}")
include(cdpm_version)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_get_version(ver)
assert_eq("${ver}" "1.2.3-alpha.1" "pre-release suffix preserved verbatim")

file(REMOVE_RECURSE "${__tmp_dir}")
message(STATUS "PASS: _cdpm_get_version accepts semver pre-release suffix")
