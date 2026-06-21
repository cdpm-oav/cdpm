# Test: generate_user_file.invalid_key
# A user key outside [a-z0-9_.-] is fatal during file generation.
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/gen_user_badkey")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/cdpm.json" [[{"cdpm_schema":1}]])
file(WRITE "${tmp}/cdpm_user.json"
[[{"packages":{"fmt":{"user":{"Bad Key!":{"value":"x"}}}}}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "${tmp}/cdpm_user.json")
cdpm_config_load(FORCE)

# Expected to abort with FATAL_ERROR (registered WILL_FAIL TRUE).
cdpm_generate_user_file("fmt" "${tmp}/out.cmake")

message(FATAL_ERROR "FAIL: expected FATAL_ERROR for invalid user key, but got none")
