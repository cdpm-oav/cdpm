# Test: compute.context_independence
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/context_indep")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(wrapper1 "${tmp}/wrapper1.cmake")
set(wrapper2 "${tmp}/subdir/wrapper2.cmake")
file(WRITE "${wrapper1}" "set(WRAPPER_VALUE 1)\n")
file(WRITE "${wrapper2}" "set(WRAPPER_VALUE 2)\n")

# Under a cdpm wrapper the hash must depend only on the semantic marker, not on
# the wrapper's own path or bytes.
set(CDPM_TOOLCHAIN_SEMANTIC_ID "deadbeef12345678")
set(CMAKE_TOOLCHAIN_FILE "${wrapper1}")
cdpm_compute_config_hash("demo" "1.0.0" "{}" h1)

set(CMAKE_TOOLCHAIN_FILE "${wrapper2}")
cdpm_compute_config_hash("demo" "1.0.0" "{}" h2)

assert_eq("${h1}" "${h2}" "same semantic marker ignores wrapper path and bytes")

# A change to a frozen allow-list value still moves the hash via tcvars.
set(ANDROID_ABI "arm64-v8a")
cdpm_compute_config_hash("demo" "1.0.0" "{}" h_abi)
assert_ne("${h1}" "${h_abi}" "changing a frozen allow-list value changes the hash")

# A change to the semantic marker itself moves the hash.
set(CDPM_TOOLCHAIN_SEMANTIC_ID "feedface87654321")
cdpm_compute_config_hash("demo" "1.0.0" "{}" h3)
assert_ne("${h1}" "${h3}" "changing the semantic marker changes the hash")

# The native sentinel contributes no tc: component: the hash equals the hash of a
# context with no toolchain at all, even when a wrapper toolchain file is in effect.
# This is what makes nested (depth-2+) hashes converge with the top-level orchestrator
# on native builds. An empty marker (wrappers from older cdpm versions) behaves the same.
unset(CDPM_TOOLCHAIN_SEMANTIC_ID)
unset(CMAKE_TOOLCHAIN_FILE)
cdpm_compute_config_hash("demo" "1.0.0" "{}" h_no_tc)

set(CDPM_TOOLCHAIN_SEMANTIC_ID "native")
set(CMAKE_TOOLCHAIN_FILE "${wrapper1}")
cdpm_compute_config_hash("demo" "1.0.0" "{}" h_sentinel)
assert_eq("${h_sentinel}" "${h_no_tc}" "sentinel marker adds no tc: component (matches no-toolchain hash)")

set(CDPM_TOOLCHAIN_SEMANTIC_ID "")
cdpm_compute_config_hash("demo" "1.0.0" "{}" h_empty)
assert_eq("${h_empty}" "${h_no_tc}" "empty legacy marker adds no tc: component")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: hash context independence via semantic marker")
