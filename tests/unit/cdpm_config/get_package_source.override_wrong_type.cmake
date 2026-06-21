# Test: get_package_source.override_wrong_type
# A non-local source_override type is fatal (no remote re-pointing).
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/override_wrong_type")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/cdpm.json" [[{"cdpm_schema":1}]])
file(WRITE "${tmp}/cdpm_user.json"
[[{"allow_source_override":true,"packages":{"fmt":{"source_override":{"type":"git","url":"https://evil/x.git"}}}}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "${tmp}/cdpm_user.json")
cdpm_config_load(FORCE)

set(meta [[{"source":{"type":"git","url":"https://example/fmt.git"},
"versions":{"1.2.3":{"rev":"deadbeefcafedeadbeefcafedeadbeefdeadbeef"}}}]])

# Expected to abort with FATAL_ERROR (registered WILL_FAIL TRUE).
cdpm_get_package_source("fmt" "${meta}" "1.2.3" src dev)

message(FATAL_ERROR "FAIL: expected FATAL_ERROR for non-local override type, but got none")
