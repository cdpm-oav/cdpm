# Test: hash.build_system_override
include(cdpm_config)
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Pin environment-sensitive inputs so only the build-system override moves the hash.
set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")

set(meta "{}")
set(pkg "testpkg")
set(version "1.0.0")

# No override -> hash1
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "{}")
cdpm_compute_config_hash("${pkg}" "${version}" "${meta}" hash1)

# Override to b2 -> hash2
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG
    [[{"packages":{"testpkg":{"build_system":"b2"}}}]])
cdpm_compute_config_hash("${pkg}" "${version}" "${meta}" hash2)

# Override to cmake -> hash3
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG
    [[{"packages":{"testpkg":{"build_system":"cmake"}}}]])
cdpm_compute_config_hash("${pkg}" "${version}" "${meta}" hash3)

assert_ne("${hash1}" "${hash2}" "build-system override changes the hash")
assert_ne("${hash2}" "${hash3}" "different build-system overrides yield different hashes")

message(STATUS "PASS: build-system override participates in the config hash")
