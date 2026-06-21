# Test: get_package_source.override_local
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# A local source_override with allow_source_override:true yields the override as
# the source and marks the build dev=TRUE.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/override_local")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/cdpm.json" [[{"cdpm_schema":1}]])
file(WRITE "${tmp}/cdpm_user.json"
[[{"allow_source_override":true,"packages":{"fmt":{"source_override":{"type":"local","path":"/home/dev/src/fmt"}}}}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "${tmp}/cdpm_user.json")
cdpm_config_load(FORCE)

set(meta [[{"source":{"type":"git","url":"https://example/fmt.git"},
"versions":{"1.2.3":{"rev":"deadbeefcafedeadbeefcafedeadbeefdeadbeef"}}}]])
cdpm_get_package_source("fmt" "${meta}" "1.2.3" src dev)

assert_true("${dev}" "local override marks the build dev")
assert_json_member("${src}" "type" "local" "override source type is local")
assert_json_member("${src}" "path" "/home/dev/src/fmt" "override path returned")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: get_package_source honours local source_override (dev)")
