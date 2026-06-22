# Test: compute.deterministic
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Same inputs -> same 16-char hash across calls.
set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")

cdpm_compute_config_hash("fmt" "10.2.1" "{}" h1)
cdpm_compute_config_hash("fmt" "10.2.1" "{}" h2)

assert_eq("${h1}" "${h2}" "hash is deterministic for identical inputs")

string(LENGTH "${h1}" len)
assert_eq("${len}" "16" "hash is 16 hex chars")
assert_match("${h1}" "^[0-9a-f]+$" "hash is lower-case hex")

message(STATUS "PASS: cdpm_compute_config_hash is deterministic and 16 hex chars")
