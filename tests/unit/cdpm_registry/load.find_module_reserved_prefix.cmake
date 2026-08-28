include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/find_module_reserved_prefix")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/packages/demo")
file(WRITE "${tmp}/packages/demo/package.json"
    [[{"find_package_name":"Demo","find_module":{"CMAKE_PROJECT_TOP_LEVEL_INCLUDES":"evil.cmake"},
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
if(NOT found)
    message(FATAL_ERROR "FAIL: demo package was not found in registry")
endif()

message(FATAL_ERROR "FAIL: reserved-prefix find_module key was accepted")
