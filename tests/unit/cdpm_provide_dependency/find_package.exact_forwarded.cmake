include(cdpm_config)
include(cdpm_provide_dependency)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/find_package_exact_forwarded")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/install/lib/cmake/Demo" "${tmp}/registry/packages/demo")
file(WRITE "${tmp}/install/lib/cmake/Demo/DemoConfig.cmake" "# Installed fixture\n")
file(WRITE "${tmp}/install/lib/cmake/Demo/DemoConfigVersion.cmake" [[
set(PACKAGE_VERSION "12.1.0")
if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
    set(PACKAGE_VERSION_COMPATIBLE TRUE)
endif()
]])
file(WRITE "${tmp}/registry/packages/demo/package.json" [[{"find_package_name":"Demo",
    "source":{"type":"git","url":"https://example.test/demo.git"},
    "default_version":"11.2.0",
    "versions":{"11.2.0":{"rev":"0123456789abcdef0123456789abcdef01234567"},
                "12.1.0":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}]])
file(WRITE "${tmp}/registry/packages.json"
    "{\"version\":1,\"packages\":{\"demo\":\"packages/demo/package.json\"}}")
file(WRITE "${tmp}/cdpm.json"
    "{\"cdpm_schema\":1,\"repos\":[{\"kind\":\"file\",\"path\":\"${tmp}/registry/packages.json\"}]}")

set(CDPM_PROJECT_DIR "${tmp}")
set(CDPM_STORE_DIR "${tmp}/store")
set(CDPM_RUNTIME_DIR "${tmp}/runtime")
function(cdpm_resolve_and_build pkg req_ver out)
    cmake_parse_arguments(arg "EXACT" "ROLE" "" ${ARGN})
    assert_eq("${req_ver}" "12.1.0" "provider forwards requested version")
    assert_true("${arg_EXACT}" "provider forwards EXACT")
    set_property(GLOBAL PROPERTY exact_forwarded TRUE)
    set(context "{}")
    _cdpm_json_set_safe("${context}" install_dir "${tmp}/install" STRING context)
    string(JSON context SET "${context}" prefixes "[]")
    string(JSON context SET "${context}" host_prefixes "[]")
    set(${out} "${context}" PARENT_SCOPE)
endfunction()

cdpm_config_load()
cdpm_load_repos()
list(PREPEND CMAKE_PREFIX_PATH "${tmp}/install")
cdpm_provide_dependency(FIND_PACKAGE Demo 12.1.0 EXACT REQUIRED)
get_property(forwarded GLOBAL PROPERTY exact_forwarded)
assert_true("${forwarded}" "managed provider called resolver")
file(REMOVE_RECURSE "${tmp}")
