# Test: get.wrong_type (expected failure)
include(cdpm_json)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_json_get(v [[{"a":1}]] PATH a EXPECT_TYPE STRING CONTEXT "cfg")
message(STATUS "unreachable: ${v}")
