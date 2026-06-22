# Test: build_system.duplicate_no_override
# Re-registering an existing driver without OVERRIDE is fatal.
include(cdpm_config)

cdpm_register_build_system("meson" "core/bs/a.cmake")

# Expected to abort with FATAL_ERROR (registered WILL_FAIL TRUE).
cdpm_register_build_system("meson" "core/bs/b.cmake")

message(FATAL_ERROR "FAIL: expected FATAL_ERROR for duplicate driver, but got none")
