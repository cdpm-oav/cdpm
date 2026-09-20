# Test: store dir precedence (CDPM_STORE_DIR > effective config store_dir > platform default) and NO_CREATE.
cmake_policy(VERSION 3.25...4.0)

include(cdpm_basics)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/resolve_store_dir")
file(REMOVE_RECURSE "${tmp}")

# 1. Explicit cache variable wins and NO_CREATE does not touch the filesystem.
set(CDPM_STORE_DIR "${tmp}/explicit-store")
_cdpm_resolve_store_dir(explicit NO_CREATE)
assert_eq("${explicit}" "${tmp}/explicit-store" "CDPM_STORE_DIR override wins")
if(EXISTS "${explicit}")
    message(FATAL_ERROR "FAIL: NO_CREATE must not create the store directory")
endif()

# Without NO_CREATE the directory is created.
_cdpm_resolve_store_dir(explicit_created)
if(NOT IS_DIRECTORY "${explicit_created}")
    message(FATAL_ERROR "FAIL: store resolution should create the directory by default")
endif()

# 2. Effective config store_dir is used when no cache override is present.
unset(CDPM_STORE_DIR)
set(eff "{}")
_cdpm_json_set_safe("${eff}" "store_dir" "${tmp}/config-store" "STRING" eff)
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "${eff}")
_cdpm_resolve_store_dir(from_config NO_CREATE)
assert_eq("${from_config}" "${tmp}/config-store" "effective config store_dir is honored")

# 3. Platform default when neither override nor config value is set.
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "{}")
_cdpm_resolve_store_dir(platform NO_CREATE)
assert_match("${platform}" "/.cdpm/store$" "platform default ends in /.cdpm/store")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm_basics store dir precedence")
