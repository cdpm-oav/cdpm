include(cdpm_config)
include("${CMAKE_CURRENT_LIST_DIR}/fixture_helpers.cmake")
init_registry_fixture(case_collision tmp)
file(WRITE "${tmp}/packages.json" [[{"version":1,"packages":{
"demo":"packages/demo/package.json","Demo":"packages/demo/package.json"}}]])
cdpm_load_repo("${tmp}/packages.json")
