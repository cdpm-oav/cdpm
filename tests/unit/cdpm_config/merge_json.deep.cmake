# Test: merge_json.deep
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Overlay deep-merges nested objects; scalars in overlay win, untouched keys kept.
set(base    [[{"a":1,"nested":{"x":1,"y":2},"keep":"base"}]])
set(overlay [[{"a":9,"nested":{"y":20,"z":30}}]])
cdpm_merge_json("${base}" "${overlay}" out)

assert_json_member("${out}" "a"    "9"    "scalar overwritten")
assert_json_member("${out}" "keep" "base" "untouched key kept")
string(JSON nested GET "${out}" "nested")
assert_json_member("${nested}" "x" "1"  "nested untouched")
assert_json_member("${nested}" "y" "20" "nested overwritten")
assert_json_member("${nested}" "z" "30" "nested added")

message(STATUS "PASS: merge_json deep-merges nested objects")
