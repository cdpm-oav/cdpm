# Test: compute.compiler_version_changes_hash
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# In script mode ENABLED_LANGUAGES is empty, so the hash falls back to whichever
# CMAKE_<LANG>_COMPILER variables are defined. A compiler VERSION bump (same id,
# same unreachable path) must change the hash -- this captures minor/patch drift.
set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")

set(CMAKE_CXX_COMPILER "/usr/bin/c++-cdpm-fake")  # non-existent -> path fallback
set(CMAKE_CXX_COMPILER_ID "GNU")

set(CMAKE_CXX_COMPILER_VERSION "13.2.0")
cdpm_compute_config_hash("fmt" "10.2.1" "{}" h_v1)

set(CMAKE_CXX_COMPILER_VERSION "13.2.1")
cdpm_compute_config_hash("fmt" "10.2.1" "{}" h_v2)

assert_ne("${h_v1}" "${h_v2}" "a compiler version bump changes the hash")

message(STATUS "PASS: per-language compiler version participates in the hash")
