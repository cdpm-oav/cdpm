# Test: config_load.layer_merge
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Project (committed) and user (non-committed) layers deep-merge; user wins on
# overlapping keys; machine layer disabled by empty path.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/config_load_layer_merge")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/cdpm.json"      [[{"cdpm_schema":1,"options":{"SHARED":true},"who":"project"}]])
file(WRITE "${tmp}/cdpm_user.json" [[{"options":{"SHARED":false},"extra":"user"}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "${tmp}/cdpm_user.json")
cdpm_config_load(FORCE)

get_property(eff GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG)
assert_json_member("${eff}" "who"   "project" "committed-only key survives")
assert_json_member("${eff}" "extra" "user"    "user-only key merged in")
string(JSON shared GET "${eff}" "options" "SHARED")
assert_eq("${shared}" "OFF" "user layer overrides project on overlapping option")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: config_load merges layers with user precedence")
