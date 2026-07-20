include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/fixture_helpers.cmake")

init_registry_fixture(valid_schema2 tmp)
file(WRITE "${tmp}/packages.json"
    [[{"repo_schema":2,"packages":{"Demo":"packages/demo/package.json"}}]])
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "")
set_property(GLOBAL PROPERTY CDPM_REPO_PROVENANCE "")
set_property(GLOBAL PROPERTY CDPM_REPO_JSON
    "{\"repos\":[{\"kind\":\"file\",\"path\":\"${tmp}/packages.json\",\"packages\":[\"de*\"]}]}")
cdpm_load_repos()

cdpm_find_in_repo(demo found meta)
assert_true("${found}" "normalized schema-2 package is registered")
assert_json_member("${meta}" find_package_name Demo "manifest metadata is materialized")
string(FIND "${meta}" "manifest_dir" leaked)
assert_eq("${leaked}" "-1" "private provenance is absent from canonical metadata")
get_property(merged GLOBAL PROPERTY CDPM_MERGED_REPO)
string(FIND "${merged}" "repo_root" merged_leak)
assert_eq("${merged_leak}" "-1" "private provenance is absent from CDPM_MERGED_REPO")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: schema-2 manifests materialize canonical metadata without provenance")
