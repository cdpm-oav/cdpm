# Test: require_exact.rejects_range (WILL_FAIL)
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Bracketed version ranges must be rejected with a clear error.
_cdpm_require_exact_version("foo" "test" "[1.0->2.0)" v)

message(STATUS "UNREACHABLE: bracketed range should have aborted")
