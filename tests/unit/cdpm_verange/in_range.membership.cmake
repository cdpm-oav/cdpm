# Test: in_range.membership
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# [10.0->12.0): 10.0 in, 11.x in, 12.0 out, 9.x out.
cdpm_version_in_range("10.0.0" "[10.0->12.0)" r)
assert_true("${r}" "10.0.0 inside [10.0->12.0)")
cdpm_version_in_range("11.5.0" "[10.0->12.0)" r)
assert_true("${r}" "11.5.0 inside")
cdpm_version_in_range("12.0.0" "[10.0->12.0)" r)
assert_false("${r}" "12.0.0 excluded by ) ")
cdpm_version_in_range("9.9.0" "[10.0->12.0)" r)
assert_false("${r}" "9.9.0 below low")

# Exclusive low (10.0->...) excludes exactly 10.0.
cdpm_version_in_range("10.0.0" "(10.0->12.0)" r)
assert_false("${r}" "10.0.0 excluded by ( ")
cdpm_version_in_range("10.0.1" "(10.0->12.0)" r)
assert_true("${r}" "10.0.1 above exclusive low")

# '*' matches anything.
cdpm_version_in_range("0.1.0" "*" r)
assert_true("${r}" "star matches all")

message(STATUS "PASS: version_in_range bound semantics")
