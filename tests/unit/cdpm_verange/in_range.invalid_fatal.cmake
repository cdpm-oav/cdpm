# Test: in_range.invalid_fatal (WILL_FAIL)
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# A malformed range is an authoring error -> fatal.
cdpm_version_in_range("1.0.0" "[10.0~~12.0)" r)

message(STATUS "UNREACHABLE: invalid range should have aborted")
