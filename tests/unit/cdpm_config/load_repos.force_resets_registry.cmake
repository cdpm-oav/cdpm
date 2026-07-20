include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/load_repos_force_resets_registry")
file(REMOVE_RECURSE "${tmp}")
foreach(repo IN ITEMS first second)
    file(MAKE_DIRECTORY "${tmp}/${repo}/pkg")
endforeach()
file(WRITE "${tmp}/first/pkg/package.json" [[{"find_package_name":"FirstAlias",
"source":{"type":"git","url":"https://first.test/pkg.git"},
"versions":{"1":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}]])
file(WRITE "${tmp}/second/pkg/package.json" [[{"find_package_name":"SecondAlias",
"source":{"type":"git","url":"https://second.test/pkg.git"},
"versions":{"1":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}]])
file(WRITE "${tmp}/first/packages.json" [[{"repo_schema":2,"packages":{"first":"pkg/package.json"}}]])
file(WRITE "${tmp}/second/packages.json" [[{"repo_schema":2,"packages":{"second":"pkg/package.json"}}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_USER_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
file(WRITE "${CDPM_PROJECT_CONFIG}"
    "{\"cdpm_schema\":1,\"repos\":[{\"kind\":\"file\",\"path\":\"${tmp}/first/packages.json\"}]}")
cdpm_config_load(FORCE)
cdpm_load_repos()
cdpm_find_package_in_repo(FirstAlias first_found first_key first_meta)
assert_true("${first_found}" "first lifecycle materializes and caches its alias")
get_property(first_ids GLOBAL PROPERTY CDPM_SCHEMA2_REGISTRY_IDS)
list(GET first_ids 0 first_id)

file(WRITE "${CDPM_PROJECT_CONFIG}"
    "{\"cdpm_schema\":1,\"repos\":[{\"kind\":\"file\",\"path\":\"${tmp}/second/packages.json\"}]}")
cdpm_config_load(FORCE)
cdpm_load_repos()

cdpm_find_package_in_repo(first old_found old_key old_meta)
assert_false("${old_found}" "a FORCE config lifecycle removes old canonical owners")
cdpm_find_package_in_repo(FirstAlias old_alias_found old_alias_key old_alias_meta)
assert_false("${old_alias_found}" "a FORCE config lifecycle removes old alias cache entries")
cdpm_find_package_in_repo(SecondAlias second_found second_key second_meta)
assert_true("${second_found}" "the replacement CDPM_REPO_JSON is loaded")
_cdpm_registry_get_provenance(first old_provenance_found old_provenance)
assert_false("${old_provenance_found}" "old materialization provenance is cleared")
get_property(old_descriptor GLOBAL PROPERTY "CDPM_SCHEMA2_${first_id}_PACKAGES")
assert_empty("${old_descriptor}" "old schema-2 descriptor properties are cleared")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: FORCE config reload starts a clean registry lifecycle")
