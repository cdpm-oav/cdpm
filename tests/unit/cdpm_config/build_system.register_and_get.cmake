# Test: build_system.register_and_get
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Built-in drivers are seeded; lookup is case-insensitive; a newly registered
# driver is retrievable.
cdpm_get_build_system("cmake" mod found)
assert_true("${found}" "built-in cmake driver seeded")
assert_match("${mod}" "cdpm_bs_cmake.cmake" "built-in module path")

cdpm_get_build_system("OpenSSL" mod found)
assert_true("${found}" "lookup is case-insensitive")

cdpm_get_build_system("meson" mod found)
assert_false("${found}" "unregistered driver not found")

cdpm_register_build_system("meson" "core/bs/cdpm_bs_meson.cmake")
cdpm_get_build_system("meson" mod found)
assert_true("${found}" "registered driver found")
assert_eq("${mod}" "core/bs/cdpm_bs_meson.cmake" "registered module path returned")

message(STATUS "PASS: build-system registry registers and resolves drivers")
