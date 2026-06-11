# Test: parse_uri.https.unknown
include(cdpm_uri)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cdpm_parse_uri("https://example.com/some/page" PREFIX dep)

assert_eq("${dep_SCHEME_TYPE}"   "HTTPS"   "scheme type")
assert_eq("${dep_RESOURCE_TYPE}" "UNKNOWN" "resource type")
message(STATUS "PASS: https without known extension -> UNKNOWN")

