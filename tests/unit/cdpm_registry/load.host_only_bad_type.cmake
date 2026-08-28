include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/host_only_bad_type")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/packages/demo")
file(WRITE "${tmp}/packages/demo/package.json"
    [[{"find_package_name":"Demo","host_only":"yes",
    "source":{"type":"git","url":"https://example.test/demo.git"},
    "default_version":"1.0.0",
    "versions":{"1.0.0":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}]]
)
file(WRITE "${tmp}/packages.json"
    "{\"version\":1,\"packages\":{\"demo\":\"packages/demo/package.json\"}}")
file(WRITE "${tmp}/cdpm.json"
    "{\"cdpm_schema\":1,\"repos\":[{\"kind\":\"file\",\"path\":\"${tmp}/packages.json\"}]}")

set(CDPM_PROJECT_DIR "${tmp}")
set(CDPM_MACHINE_CONFIG "")
set(CDPM_USER_CONFIG "")
cdpm_config_load()
cdpm_load_repos()
cdpm_find_package_in_repo(demo found key meta)

message(FATAL_ERROR "FAIL: non-boolean host_only was accepted")
