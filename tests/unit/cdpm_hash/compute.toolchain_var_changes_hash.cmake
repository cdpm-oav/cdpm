# Test: compute.toolchain_var_changes_hash
include(cdpm_toolchain)
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# A change to an IDE-injected toolchain variable (allow-list, e.g. ANDROID_ABI)
# must change the config hash even with no toolchain file present.
set(CMAKE_SYSTEM_NAME "Android")
set(CMAKE_SYSTEM_PROCESSOR "aarch64")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")

set(ANDROID_ABI "arm64-v8a")
cdpm_compute_config_hash("fmt" "10.2.1" "{}" h_abi1)

set(ANDROID_ABI "armeabi-v7a")
cdpm_compute_config_hash("fmt" "10.2.1" "{}" h_abi2)

assert_ne("${h_abi1}" "${h_abi2}" "changing ANDROID_ABI changes the hash")

set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
cdpm_compute_config_hash("fmt" "10.2.1" "{}" h_root_mode1)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY NEVER)
cdpm_compute_config_hash("fmt" "10.2.1" "{}" h_root_mode2)
assert_ne("${h_root_mode1}" "${h_root_mode2}" "changing a root-path mode changes the hash")

message(STATUS "PASS: frozen toolchain variables participate in the config hash")
