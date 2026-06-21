# Test: config_load.security.user_integrity
# A per-package integrity field in a non-committed (user) layer is fatal.
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/security_user_integrity")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/cdpm.json"      [[{"cdpm_schema":1}]])
file(WRITE "${tmp}/cdpm_user.json" [[{"packages":{"fmt":{"sha256":"deadbeef"}}}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "${tmp}/cdpm_user.json")

# Expected to abort with FATAL_ERROR (registered WILL_FAIL TRUE).
cdpm_config_load(FORCE)

message(FATAL_ERROR "FAIL: expected FATAL_ERROR for user-layer integrity override, but got none")
