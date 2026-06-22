# Test: parse.brackets
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Half-open [a->b): inclusive low, exclusive high.
cdpm_parse_version_range("[10.0->12.0)" low high low_incl high_incl ok)
assert_true("${ok}" "half-open range parses")
assert_eq("${low}"  "10.0" "low bound")
assert_eq("${high}" "12.0" "high bound")
assert_true("${low_incl}"   "low inclusive")
assert_false("${high_incl}" "high exclusive")

# Fully closed (a->b].
cdpm_parse_version_range("(1.0->2.0]" low high low_incl high_incl ok)
assert_true("${ok}" "exclusive-low/inclusive-high parses")
assert_false("${low_incl}" "low exclusive")
assert_true("${high_incl}" "high inclusive")

message(STATUS "PASS: parse_version_range handles bracket inclusivity")
