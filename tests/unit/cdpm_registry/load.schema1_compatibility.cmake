include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/schema1_compatibility")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/packages.json" [[{"repo_schema":1,"packages":{"Demo":{
"source":{"type":"git","url":"https://example.test/demo.git"},
"versions":{"1.0.0":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}}}]])
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "")
set_property(GLOBAL PROPERTY CDPM_REPO_PROVENANCE "")
cdpm_load_repo("${tmp}/packages.json")
cdpm_find_in_repo(DEMO found meta)
assert_true("${found}" "schema 1 remains readable and case-insensitive")
string(JSON rev GET "${meta}" versions 1.0.0 rev)
assert_eq("${rev}" "0123456789abcdef0123456789abcdef01234567" "schema-1 metadata is unchanged")
file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: schema 1 remains compatible")
