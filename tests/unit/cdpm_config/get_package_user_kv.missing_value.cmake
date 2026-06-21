# Test: get_package_user_kv.missing_value
# A user entry without a `value` is fatal.
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/user_kv_missing")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/cdpm.json" [[{"cdpm_schema":1}]])
file(WRITE "${tmp}/cdpm_user.json"
[[{"packages":{"fmt":{"user":{"myorg.fips":{"tracked":true}}}}}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "${tmp}/cdpm_user.json")
cdpm_config_load(FORCE)

# Expected to abort with FATAL_ERROR (registered WILL_FAIL TRUE).
cdpm_get_package_user_kv("fmt" tracked untracked)

message(FATAL_ERROR "FAIL: expected FATAL_ERROR for missing user value, but got none")
