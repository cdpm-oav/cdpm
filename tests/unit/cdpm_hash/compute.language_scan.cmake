# Test: compute.language_scan
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")

# With no compiler variables defined there is no lang contribution.
cdpm_compute_config_hash("demo" "1.0.0" "{}" no_langs)

# Define compilers out of canonical order.
set(CMAKE_CXX_COMPILER "/usr/bin/c++-cdpm-fake")
set(CMAKE_CXX_COMPILER_ID "GNU")
set(CMAKE_CXX_COMPILER_VERSION "13.0.0")

set(CMAKE_C_COMPILER "/usr/bin/cc-cdpm-fake")
set(CMAKE_C_COMPILER_ID "GNU")
set(CMAKE_C_COMPILER_VERSION "13.0.0")

cdpm_compute_config_hash("demo" "1.0.0" "{}" with_langs)

# The ENABLED_LANGUAGES global property must not override the variable scan.
set_property(GLOBAL PROPERTY ENABLED_LANGUAGES "CXX")
cdpm_compute_config_hash("demo" "1.0.0" "{}" enabled_only)
assert_eq("${with_langs}" "${enabled_only}" "hash ignores ENABLED_LANGUAGES and uses defined compiler vars")

# Order of variable definition must not matter.
unset(CMAKE_CXX_COMPILER)
unset(CMAKE_C_COMPILER)
unset(CMAKE_CXX_COMPILER_ID)
unset(CMAKE_C_COMPILER_ID)
unset(CMAKE_CXX_COMPILER_VERSION)
unset(CMAKE_C_COMPILER_VERSION)

set(CMAKE_C_COMPILER "/usr/bin/cc-cdpm-fake")
set(CMAKE_C_COMPILER_ID "GNU")
set(CMAKE_C_COMPILER_VERSION "13.0.0")
set(CMAKE_CXX_COMPILER "/usr/bin/c++-cdpm-fake")
set(CMAKE_CXX_COMPILER_ID "GNU")
set(CMAKE_CXX_COMPILER_VERSION "13.0.0")
cdpm_compute_config_hash("demo" "1.0.0" "{}" order1)

unset(CMAKE_C_COMPILER)
unset(CMAKE_CXX_COMPILER)
unset(CMAKE_C_COMPILER_ID)
unset(CMAKE_CXX_COMPILER_ID)
unset(CMAKE_C_COMPILER_VERSION)
unset(CMAKE_CXX_COMPILER_VERSION)

set(CMAKE_CXX_COMPILER "/usr/bin/c++-cdpm-fake")
set(CMAKE_CXX_COMPILER_ID "GNU")
set(CMAKE_CXX_COMPILER_VERSION "13.0.0")
set(CMAKE_C_COMPILER "/usr/bin/cc-cdpm-fake")
set(CMAKE_C_COMPILER_ID "GNU")
set(CMAKE_C_COMPILER_VERSION "13.0.0")
cdpm_compute_config_hash("demo" "1.0.0" "{}" order2)

assert_eq("${order1}" "${order2}" "language ordering is deterministic")

message(STATUS "PASS: language scan uses defined compiler vars deterministically")
