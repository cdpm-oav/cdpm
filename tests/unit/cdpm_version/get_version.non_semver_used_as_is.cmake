# Test: get_version.non_semver_used_as_is
# Non-semver content emits a warning but is returned verbatim (no fallback,
# no fatal error -- the CLI banner must keep working on dev checkouts).

set(__tmp_dir "${CMAKE_CURRENT_LIST_DIR}/_tmp/non_semver_used_as_is")
file(MAKE_DIRECTORY "${__tmp_dir}")
set(__tmp_version "${__tmp_dir}/VERSION")
file(WRITE "${__tmp_version}" "dev-build\n")

set(__CDPM_VERSION_FILE "${__tmp_version}")
include(cdpm_version)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_get_version(ver)
assert_eq("${ver}" "dev-build" "non-semver content returned verbatim")

file(REMOVE_RECURSE "${__tmp_dir}")
message(STATUS "PASS: _cdpm_get_version preserves non-semver content")
