# Test: compute.build_type_changes_hash
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_GENERATOR "Ninja")

set(CMAKE_BUILD_TYPE "Release")
cdpm_compute_config_hash("fmt" "10.2.1" "{}" h_release)

set(CMAKE_BUILD_TYPE "Debug")
cdpm_compute_config_hash("fmt" "10.2.1" "{}" h_debug)

assert_ne("${h_release}" "${h_debug}" "changing CMAKE_BUILD_TYPE changes the hash")

message(STATUS "PASS: build type participates in the config hash")
