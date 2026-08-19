# Test: require_exact.rejects_malformed (WILL_FAIL)
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Malformed range tokens (ellipsis form) must be rejected, not silently mis-compared.
_cdpm_require_exact_version("foo" "test" "9.0...10.0" v)

message(STATUS "UNREACHABLE: malformed range should have aborted")
