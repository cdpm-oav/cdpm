# Test: in_ranges.forms_and_excludes
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# String form + exclude hole.
cdpm_version_in_ranges("11.0.0" "\"[10.0->12.0)\"" "[\"10.2.1\"]" r)
assert_true("${r}" "11.0.0 in range, not excluded")
cdpm_version_in_ranges("10.2.1" "\"[10.0->12.0)\"" "[\"10.2.1\"]" r)
assert_false("${r}" "10.2.1 excluded hole")

# Array-of-versions form (each is an exact point match).
cdpm_version_in_ranges("10.1.1" "[\"10.0.0\",\"10.1.1\"]" "" r)
assert_true("${r}" "10.1.1 in explicit array")
cdpm_version_in_ranges("10.2.0" "[\"10.0.0\",\"10.1.1\"]" "" r)
assert_false("${r}" "10.2.0 not in explicit array")

# Object form {from,to,from_include,to_include}.
cdpm_version_in_ranges("11.5.0" "{\"from\":\"10.0\",\"to\":\"12.0\",\"from_include\":true,\"to_include\":false}" "" r)
assert_true("${r}" "11.5.0 in object range")
cdpm_version_in_ranges("12.0.0" "{\"from\":\"10.0\",\"to\":\"12.0\",\"from_include\":true,\"to_include\":false}" "" r)
assert_false("${r}" "12.0.0 excluded by to_include=false")

# Absent applies_to (empty) matches all.
cdpm_version_in_ranges("99.0.0" "" "" r)
assert_true("${r}" "absent applies_to matches all")

message(STATUS "PASS: version_in_ranges handles all three forms + excludes")
