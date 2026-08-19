# Test: require_exact.rejects_star (WILL_FAIL)
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# The "any version" wildcard must be rejected.
_cdpm_require_exact_version("foo" "test" "*" v)

message(STATUS "UNREACHABLE: wildcard range should have aborted")
