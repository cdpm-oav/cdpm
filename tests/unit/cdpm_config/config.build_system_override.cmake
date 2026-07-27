# Test: config.build_system_override
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# No override -> out_found is FALSE.
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "{}")
cdpm_get_package_build_system_override("boost" value found)
assert_eq("${value}" "" "no override: value is empty")
assert_false("${found}" "no override: found is FALSE")

# Override set to "b2" -> returns "b2", out_found is TRUE.
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG [[{"packages":{"boost":{"build_system":"b2"}}}]])
cdpm_get_package_build_system_override("boost" value found)
assert_eq("${value}" "b2" "b2 override: value is b2")
assert_true("${found}" "b2 override: found is TRUE")

# Override set to "B2" (uppercase) -> returns lower-cased "b2".
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG [[{"packages":{"boost":{"build_system":"B2"}}}]])
cdpm_get_package_build_system_override("boost" value found)
assert_eq("${value}" "b2" "uppercase override: value is lower-cased")
assert_true("${found}" "uppercase override: found is TRUE")

set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "")
message(STATUS "PASS: build_system override read from user config")
