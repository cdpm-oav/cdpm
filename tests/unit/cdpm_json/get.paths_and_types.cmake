# Test: get.paths_and_types
include(cdpm_json)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(doc [[{"a":{"b":[10,20]},"s":"hi","f":false,"n":null,"num":7}]])

_cdpm_json_get(v "${doc}" PATH a b 1 OUT_TYPE t)
assert_eq("${v}" "20" "nested path get")
assert_eq("${t}" "NUMBER" "nested path type")

_cdpm_json_get(s "${doc}" PATH s OUT_TYPE st)
assert_eq("${s}" "hi" "string value")
assert_eq("${st}" "STRING" "string type")

_cdpm_json_get(b "${doc}" PATH f OUT_TYPE bt)
assert_eq("${bt}" "BOOLEAN" "boolean type")

# Absent path -> default, type empty.
_cdpm_json_get(m "${doc}" PATH missing DEFAULT "fallback" OUT_TYPE mt)
assert_eq("${m}" "fallback" "missing yields default")
assert_empty("${mt}" "missing yields empty type")

_cdpm_json_has(h1 "${doc}" PATH a b)
assert_true("${h1}" "existing path present")
_cdpm_json_has(h2 "${doc}" PATH nope)
assert_false("${h2}" "absent path not present")

_cdpm_json_length(la "${doc}" PATH a b)
assert_eq("${la}" "2" "array length")
_cdpm_json_length(lm "${doc}" PATH missing)
assert_eq("${lm}" "0" "missing length is 0")

_cdpm_json_type(tn "${doc}" PATH n)
assert_eq("${tn}" "NULL" "null type")

message(STATUS "PASS: json get/has/length/type over paths")
