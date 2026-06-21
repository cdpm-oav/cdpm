# Test: get_package_user_kv.tracked_split
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# The single `user` section is split by each entry's `tracked` flag (default true);
# only `value` is emitted. Tracked feeds config_hash; untracked (secrets) does not.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/user_kv")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/cdpm.json" [[{"cdpm_schema":1}]])
file(WRITE "${tmp}/cdpm_user.json"
[[{"packages":{"fmt":{"user":{"myorg.fips":{"value":"on"},"myorg.token":{"value":"s3cr3t","tracked":false}}}}}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "${tmp}/cdpm_user.json")
cdpm_config_load(FORCE)

cdpm_get_package_user_kv("fmt" tracked untracked)

assert_json_member("${tracked}"   "myorg.fips"  "on"     "tracked default-true key emits value")
assert_json_member("${untracked}" "myorg.token" "s3cr3t" "untracked key emits value")

# The tracked map must NOT contain the secret, and vice versa.
string(JSON probe1 ERROR_VARIABLE e1 GET "${tracked}"   "myorg.token")
assert_true("${e1}" "secret stays out of tracked map")
string(JSON probe2 ERROR_VARIABLE e2 GET "${untracked}" "myorg.fips")
assert_true("${e2}" "tracked key stays out of untracked map")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: get_package_user_kv splits by tracked flag")
