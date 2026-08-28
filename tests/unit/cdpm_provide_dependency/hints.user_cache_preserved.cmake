include(cdpm_config)
include(cdpm_provide_dependency)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/hints_user_cache_preserved")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/install/lib/cmake/Demo")
file(WRITE "${tmp}/install/lib/cmake/Demo/DemoConfig.cmake" "#")

file(MAKE_DIRECTORY "${tmp}/registry/packages/demo")
file(WRITE "${tmp}/registry/packages/demo/package.json"
    [[{"find_package_name":"Demo","find_module":{"DEMO_HINT":"lib/cmake"},
    "source":{"type":"git","url":"https://example.test/demo.git"},
    "default_version":"1.0.0",
    "versions":{"1.0.0":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}]]
)
file(WRITE "${tmp}/registry/packages.json"
    "{\"version\":1,\"packages\":{\"demo\":\"packages/demo/package.json\"}}")
file(WRITE "${tmp}/cdpm.json"
    "{\"cdpm_schema\":1,\"repos\":[{\"kind\":\"file\",\"path\":\"${tmp}/registry/packages.json\"}]}")

set(CDPM_PROJECT_DIR "${tmp}")
set(CDPM_STORE_DIR "${tmp}/store")
set(CDPM_RUNTIME_DIR "${tmp}/runtime")

function(cdpm_resolve_and_build pkg req_ver out)
    set(context "{}")
    _cdpm_json_set_safe("${context}" install_dir "${tmp}/install" STRING context)
    string(JSON context SET "${context}" prefixes "[]")
    string(JSON context SET "${context}" host_prefixes "[]")
    string(JSON context SET "${context}" managed "{}")
    string(JSON context SET "${context}" host_managed "{}")
    set(${out} "${context}" PARENT_SCOPE)
endfunction()

cdpm_config_load()
cdpm_load_repos()

set(DEMO_HINT "/user/value" CACHE FILEPATH "" FORCE)
list(APPEND CMAKE_PREFIX_PATH "${tmp}/install")
cdpm_provide_dependency(FIND_PACKAGE Demo)

get_property(val CACHE DEMO_HINT PROPERTY VALUE)
assert_eq("${val}" "/user/value" "find_module hint does not clobber an existing cache value")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: find_module hints preserve existing user cache values")
