include(cdpm_config)
include(cdpm_provide_dependency)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/host_only_role")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/install/lib/cmake/Demo")
file(WRITE "${tmp}/install/lib/cmake/Demo/DemoConfig.cmake" "#")

file(MAKE_DIRECTORY "${tmp}/registry/packages/demo")
file(WRITE "${tmp}/registry/packages/demo/package.json"
    [[{"find_package_name":"Demo","host_only":true,
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

set_property(GLOBAL PROPERTY captured_role "")
function(cdpm_resolve_and_build pkg req_ver out)
    cmake_parse_arguments(arg "" "ROLE" "" ${ARGN})
    set_property(GLOBAL PROPERTY captured_role "${arg_ROLE}")
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

list(APPEND CMAKE_PREFIX_PATH "${tmp}/install")
cdpm_provide_dependency(FIND_PACKAGE Demo)

get_property(captured_role GLOBAL PROPERTY captured_role)
assert_eq("${captured_role}" "HOST" "host_only package is resolved in the HOST role")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: host_only packages resolve in the HOST role")
