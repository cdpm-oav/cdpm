# Test: version_satisfies
include(cdpm_version)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_version_satisfies("2.0" "" "2.0" ok)
assert_true("${ok}" "exact request without compatibility")
_cdpm_version_satisfies("1.5" "" "2.0" ok)
assert_false("${ok}" "non-exact request without compatibility")
_cdpm_version_satisfies("1.5" "1.0" "2.0" ok)
assert_true("${ok}" "request inside compatibility interval")
_cdpm_version_satisfies("0.9" "1.0" "2.0" ok)
assert_false("${ok}" "request below compatibility interval")
