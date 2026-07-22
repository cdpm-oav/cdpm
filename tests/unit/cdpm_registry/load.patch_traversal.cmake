include(cdpm_config)
include("${CMAKE_CURRENT_LIST_DIR}/fixture_helpers.cmake")
init_registry_fixture(patch_traversal tmp)
file(WRITE "${tmp}/packages/demo/package.json" [[{"source":{"type":"git","url":"https://example.test/demo.git"},
"patches":[{"file":"../patch.diff"}],"versions":{"1.0.0":{
"rev":"0123456789abcdef0123456789abcdef01234567"}}}]])
file(WRITE "${tmp}/packages.json" [[{"version":1,"packages":{"demo":"packages/demo/package.json"}}]])
cdpm_load_repo("${tmp}/packages.json")
cdpm_find_in_repo(demo found meta)
