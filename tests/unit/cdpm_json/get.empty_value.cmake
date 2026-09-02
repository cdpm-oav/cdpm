# Test: get.empty_value (expected failure)
include(cdpm_json)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_json_get(v [[{"a":""}]] PATH a NON_EMPTY CONTEXT "cfg")
message(STATUS "unreachable: ${v}")
