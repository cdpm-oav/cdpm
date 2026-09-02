# Test: get.required_missing (expected failure)
include(cdpm_json)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_json_get(v [[{"a":1}]] PATH b REQUIRED CONTEXT "cfg")
message(STATUS "unreachable: ${v}")
