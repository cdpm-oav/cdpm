# Test: compute.host_profile
include(cdpm_toolchain)
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_SYSROOT iphonesimulator)

# Baseline: host and target profiles must differ.
cdpm_compute_config_hash(tool 1 "{}" target_hash)
cdpm_compute_config_hash(tool 1 "{}" host_hash HOST)
assert_ne("${target_hash}" "${host_hash}" "host and target profiles have distinct hashes")

# Host compiler identity (native): changing the C compiler binary must change the HOST hash.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp_host_profile")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(CMAKE_C_COMPILER "${tmp}/host_cc_v1")
file(WRITE "${CMAKE_C_COMPILER}" "compiler v1")
cdpm_compute_config_hash(tool 1 "{}" host_v1 HOST)

set(CMAKE_C_COMPILER "${tmp}/host_cc_v2")
file(WRITE "${CMAKE_C_COMPILER}" "compiler v2")
cdpm_compute_config_hash(tool 1 "{}" host_v2 HOST)
assert_ne("${host_v1}" "${host_v2}" "native host compiler binary change changes HOST hash")

# Reset to v1 and vary build type / generator: HOST hash must stay unchanged.
set(CMAKE_C_COMPILER "${tmp}/host_cc_v1")
file(WRITE "${CMAKE_C_COMPILER}" "compiler v1")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")
cdpm_compute_config_hash(tool 1 "{}" host_release_ninja HOST)
set(CMAKE_BUILD_TYPE "Debug")
set(CMAKE_GENERATOR "Unix Makefiles")
cdpm_compute_config_hash(tool 1 "{}" host_debug_makefiles HOST)
assert_eq("${host_release_ninja}" "${host_debug_makefiles}"
    "HOST hash ignores build type and generator")

# Cross-compiling: CMAKE_C_COMPILER is the TARGET compiler and must NOT reach the HOST hash.
# Varying it must not move the hash, and the hash must equal a compiler-less platform slot.
set(CMAKE_CROSSCOMPILING TRUE)
cdpm_compute_config_hash(tool 1 "{}" host_cross_v1 HOST)
set(CMAKE_C_COMPILER "${tmp}/host_cc_v2")
cdpm_compute_config_hash(tool 1 "{}" host_cross_v2 HOST)
assert_eq("${host_cross_v1}" "${host_cross_v2}"
    "cross HOST hash ignores the (target) C compiler")
set(CMAKE_C_COMPILER "")
cdpm_compute_config_hash(tool 1 "{}" host_cross_no_cc HOST)
assert_eq("${host_cross_v1}" "${host_cross_no_cc}"
    "cross HOST hash equals the platform-only slot")

file(REMOVE_RECURSE "${tmp}")
unset(CMAKE_C_COMPILER)
unset(CMAKE_CROSSCOMPILING)
message(STATUS "PASS: compute.host_profile")
