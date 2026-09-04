# Test: keys_and_arrays
include(cdpm_json)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(doc [[{"obj":{"k1":1,"k2":2},"arr":["x","y","z"],"empty":{}}]])

_cdpm_json_keys(keys "${doc}" PATH obj)
list(LENGTH keys nkeys)
assert_eq("${nkeys}" "2" "object key count")
list(GET keys 0 k0)
assert_eq("${k0}" "k1" "first key")

_cdpm_json_keys(ek "${doc}" PATH empty)
assert_empty("${ek}" "empty object has no keys")

_cdpm_json_keys(mk "${doc}" PATH missing)
assert_empty("${mk}" "missing object has no keys")

_cdpm_json_array_to_list(items "${doc}" PATH arr)
list(JOIN items "," joined)
assert_eq("${joined}" "x,y,z" "array to list")

_cdpm_json_array_to_list(mi "${doc}" PATH missing)
assert_empty("${mi}" "missing array yields empty list")

# Top-level keys (no PATH).
_cdpm_json_keys(tk "${doc}")
list(LENGTH tk ntop)
assert_eq("${ntop}" "3" "lists top-level keys")

message(STATUS "PASS: json keys and array helpers")
