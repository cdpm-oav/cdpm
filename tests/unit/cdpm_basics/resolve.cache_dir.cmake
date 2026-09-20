# Test: cache dir resolution honors CDPM_CACHE_PATH and the binary-dir default; never creates the dir.
cmake_policy(VERSION 3.25...4.0)

include(cdpm_basics)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/resolve_cache_dir")
file(REMOVE_RECURSE "${tmp}")
set(CMAKE_BINARY_DIR "${tmp}/build")

# Default: <binary>/.cdpm, not created. The module seeds a CDPM_CACHE_PATH cache entry at include time
# (keyed to the test process binary dir); clear it so the default branch is exercised.
unset(CDPM_CACHE_PATH CACHE)
unset(CDPM_CACHE_PATH)
_cdpm_resolve_cache_dir(default_cache)
assert_eq("${default_cache}" "${tmp}/build/.cdpm" "cache dir defaults to CMAKE_BINARY_DIR/.cdpm")
if(EXISTS "${default_cache}")
    message(FATAL_ERROR "FAIL: cache resolution must not create the directory")
endif()

# Absolute override wins.
set(CDPM_CACHE_PATH "${tmp}/custom-cache")
_cdpm_resolve_cache_dir(override_cache)
assert_eq("${override_cache}" "${tmp}/custom-cache" "absolute CDPM_CACHE_PATH overrides the default")

# Relative override is normalized against CMAKE_BINARY_DIR.
set(CDPM_CACHE_PATH "../rel/./cache")
_cdpm_resolve_cache_dir(rel_cache)
assert_eq("${rel_cache}" "${tmp}/rel/cache" "relative CDPM_CACHE_PATH normalizes from CMAKE_BINARY_DIR")

message(STATUS "PASS: cdpm_basics cache dir resolution")
