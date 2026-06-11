# Test: parse_uri.file
include(cdpm_uri)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# file:/path — scheme_specific = /opt/local/cdpm
cdpm_parse_uri("file:/opt/local/cdpm" PREFIX dep)

assert_eq("${dep_SCHEME_TYPE}"   "FILE"             "scheme type")
assert_eq("${dep_FULL_URI}"      "/opt/local/cdpm"  "full URI strips file:")
assert_eq("${dep_RESOURCE_TYPE}" "LOCAL_PATH"       "resource type")
message(STATUS "PASS: file: -> FILE / LOCAL_PATH")
