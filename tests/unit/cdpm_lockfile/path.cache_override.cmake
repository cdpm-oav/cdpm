include(cdpm_lockfile)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/path_cache_override")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(CDPM_LOCKFILE_PATH "${tmp}/custom.lock.json" CACHE FILEPATH "" FORCE)
_cdpm_lockfile_default_path(path1)
assert_eq("${path1}" "${tmp}/custom.lock.json" "CDPM_LOCKFILE_PATH overrides the default lockfile path")

unset(CDPM_LOCKFILE_PATH CACHE)
set(CDPM_PROJECT_DIR "${tmp}")
_cdpm_lockfile_default_path(path2)
assert_eq("${path2}" "${tmp}/cdpm.lock.json" "default lockfile path falls back to <project>/cdpm.lock.json")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: lockfile default path respects CDPM_LOCKFILE_PATH")
