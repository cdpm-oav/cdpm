# Test: canonical_json.sorts_keys
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Canonical form sorts object keys recursively and normalizes booleans to true/false.
set(input [[{"b":2,"a":{"d":true,"c":false}}]])
cdpm_canonical_json("${input}" out)

# Semantic equality holds regardless of order.
assert_json_eq("${out}" [[{"a":{"c":false,"d":true},"b":2}]] "canonical is semantically equal")

# 'a' must appear before 'b' in the serialized text (keys sorted).
string(FIND "${out}" "\"a\"" pos_a)
string(FIND "${out}" "\"b\"" pos_b)
set(ordered FALSE)
if(pos_a LESS pos_b)
    set(ordered TRUE)
endif()
assert_true(ordered "key 'a' is serialized before key 'b'")

# Booleans normalized to JSON true/false (not ON/OFF).
assert_match("${out}" "true" "boolean true normalized")
assert_match("${out}" "false" "boolean false normalized")

message(STATUS "PASS: canonical_json sorts keys and normalizes booleans")
