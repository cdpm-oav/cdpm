# Test: config.build_system_override.unregistered
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# An override that names an unregistered driver must raise FATAL_ERROR.
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG [[{"packages":{"boost":{"build_system":"meson"}}}]])
cdpm_get_package_build_system_override("boost" value found)

# Should never reach here.
message(FATAL_ERROR "FAIL: unregistered build_system override did not raise FATAL_ERROR")
