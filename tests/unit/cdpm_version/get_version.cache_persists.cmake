# Test: get_version.cache_persists
# Verifies that _cdpm_get_version loads the value on its first call and does
# NOT re-read the VERSION file on subsequent calls. Proof:
# mutate the file between two calls and assert the cached value persists.

set(__tmp_dir "${CMAKE_CURRENT_LIST_DIR}/_tmp/cache_persists")
file(MAKE_DIRECTORY "${__tmp_dir}")
set(__tmp_version "${__tmp_dir}/VERSION")

set(__CDPM_VERSION_FILE "${__tmp_version}")
include(cdpm_version)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Creating the file after inclusion proves that loading is deferred until this call.
file(WRITE "${__tmp_version}" "7.8.9\n")
_cdpm_get_version(ver1)
assert_eq("${ver1}" "7.8.9" "first call returns file content")

# Mutate the source file: a non-cached implementation would pick this up.
file(WRITE "${__tmp_version}" "9.9.9\n")

_cdpm_get_version(ver2)
assert_eq("${ver2}" "7.8.9" "second call returns cached value, not re-read file")

file(REMOVE_RECURSE "${__tmp_dir}")
message(STATUS "PASS: _cdpm_get_version lazily caches version on first call")
