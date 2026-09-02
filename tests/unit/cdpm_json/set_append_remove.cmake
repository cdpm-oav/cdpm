# Test: set_append_remove
include(cdpm_json)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(doc "{}")

# String is escaped and quoted.
_cdpm_json_set(doc [[a"b\c]] TYPE STRING PATH s)
_cdpm_json_get(s "${doc}" PATH s OUT_TYPE st)
assert_eq("${s}" [[a"b\c]] "string round-trips with escapes")
assert_eq("${st}" "STRING" "stored as string")

# Boolean normalized.
_cdpm_json_set(doc ON TYPE BOOLEAN PATH flag)
assert_match("${doc}" "\"flag\"[ ]*:[ ]*true" "boolean ON -> true")

# Null literal.
_cdpm_json_set(doc "" TYPE NULL PATH z)
_cdpm_json_type(zt "${doc}" PATH z)
assert_eq("${zt}" "NULL" "null stored")

# Number verbatim.
_cdpm_json_set(doc 42 TYPE NUMBER PATH n)
_cdpm_json_get(n "${doc}" PATH n)
assert_eq("${n}" "42" "number stored")

# Value containing ';' survives (payload is positional, not ARGN-split).
_cdpm_json_set(doc "a;b;c" TYPE STRING PATH semi)
_cdpm_json_get(semi "${doc}" PATH semi)
assert_eq("${semi}" "a;b;c" "semicolon value round-trips")

# Append to array.
_cdpm_json_set(doc "[]" TYPE ARRAY PATH arr)
_cdpm_json_append(doc "first" TYPE STRING PATH arr)
_cdpm_json_append(doc "second" TYPE STRING PATH arr)
_cdpm_json_length(alen "${doc}" PATH arr)
assert_eq("${alen}" "2" "append grows array")
_cdpm_json_get(a1 "${doc}" PATH arr 1)
assert_eq("${a1}" "second" "appended value at index 1")

# Remove: present then tolerant-absent.
_cdpm_json_remove(doc PATH n)
_cdpm_json_has(hn "${doc}" PATH n)
assert_false("${hn}" "removed key gone")
_cdpm_json_remove(doc PATH does_not_exist)
assert_true("${doc}" "tolerant remove keeps doc")

# Equal.
_cdpm_json_equal(eq [[{"x":1,"y":2}]] [[{"y":2,"x":1}]])
assert_true("${eq}" "semantic equality ignores key order")
_cdpm_json_equal(neq [[{"x":1}]] [[{"x":2}]])
assert_false("${neq}" "different values not equal")

# encode_string.
_cdpm_json_encode_string(enc [[q"\t]])
assert_eq("${enc}" [["q\"\\t"]] "encode escapes quote and backslash")

message(STATUS "PASS: json set/append/remove/equal/encode")
