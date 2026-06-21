# Test: merge_json.remove_operator
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# The `!` suffix operator with a `null` value removes a key from the base;
# with a non-null value it forces a full replace (deep merge disabled).
set(base    [[{"keep":"yes","drop":"old","swap":{"deep":1}}]])
set(overlay [[{"drop!":null,"swap!":"flat"}]])
cdpm_merge_json("${base}" "${overlay}" out)

assert_json_member("${out}" "keep" "yes" "non-targeted key kept")
string(JSON probe ERROR_VARIABLE err GET "${out}" "drop")
set(removed FALSE)
if(err)
    set(removed TRUE)
endif()
assert_true(removed "'drop' must be removed by the ! operator")

# Non-null `!` value replaces wholesale: the deep object is gone, scalar wins.
assert_json_member("${out}" "swap" "flat" "'swap!' replaces the object with a scalar")

message(STATUS "PASS: merge_json ! operator removes and replaces keys")
