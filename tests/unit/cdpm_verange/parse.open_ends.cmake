# Test: parse.open_ends
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Open high end [a->).
cdpm_parse_version_range("[10.0->)" low high low_incl high_incl ok)
assert_true("${ok}" "open high end parses")
assert_eq("${low}"  "10.0" "low bound")
assert_empty("${high}" "high bound open")

# Open low end (->12.0].
cdpm_parse_version_range("(->12.0]" low high low_incl high_incl ok)
assert_true("${ok}" "open low end parses")
assert_empty("${low}" "low bound open")
assert_eq("${high}" "12.0" "high bound")

# '*' is fully open and inclusive.
cdpm_parse_version_range("*" low high low_incl high_incl ok)
assert_true("${ok}" "star parses")
assert_empty("${low}"  "star low open")
assert_empty("${high}" "star high open")

# Single version -> closed point range.
cdpm_parse_version_range("11.2.0" low high low_incl high_incl ok)
assert_true("${ok}" "single version parses")
assert_eq("${low}"  "11.2.0" "point low")
assert_eq("${high}" "11.2.0" "point high")

message(STATUS "PASS: parse_version_range handles open ends, star, single version")
