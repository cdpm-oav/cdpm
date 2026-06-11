# Test: parse_uri.plain.local_path
include(cdpm_uri)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cdpm_parse_uri("/opt/local/cdpm" PREFIX abs)
assert_eq("${abs_SCHEME_TYPE}"   "PLAIN"      "scheme type absolute")
assert_eq("${abs_RESOURCE_TYPE}" "LOCAL_PATH" "resource type absolute path")

cdpm_parse_uri("./vendor/cdpm" PREFIX rel)
assert_eq("${rel_SCHEME_TYPE}"   "PLAIN"      "scheme type relative ./")
assert_eq("${rel_RESOURCE_TYPE}" "LOCAL_PATH" "resource type relative path")

cdpm_parse_uri("../sibling" PREFIX rel2)
assert_eq("${rel2_RESOURCE_TYPE}" "LOCAL_PATH" "resource type relative ../")
message(STATUS "PASS: plain local paths -> LOCAL_PATH")

