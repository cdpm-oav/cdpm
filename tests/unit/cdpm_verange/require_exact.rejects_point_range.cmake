# Test: require_exact.rejects_point_range (WILL_FAIL)
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Even a closed point range written in bracket syntax must be rejected as a range request.
_cdpm_require_exact_version("foo" "test" "[1.2.3->1.2.3]" v)

message(STATUS "UNREACHABLE: point bracket range should have aborted")
