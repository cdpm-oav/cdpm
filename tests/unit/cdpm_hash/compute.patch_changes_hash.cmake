# Test: compute.patch_changes_hash
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Editing a declared patch file must change the hash (content is SHA-256'd).
set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/patch_hash")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(patch "${tmp}/0001-fix.patch")

set(meta "{\"versions\":{\"1.0.0\":{\"patches\":[\"${patch}\"]}}}")

file(WRITE "${patch}" "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n")
cdpm_compute_config_hash("fmt" "1.0.0" "${meta}" h_before)

file(WRITE "${patch}" "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+changed\n")
cdpm_compute_config_hash("fmt" "1.0.0" "${meta}" h_after)

assert_ne("${h_before}" "${h_after}" "editing a patch changes the hash")

# A hash WITHOUT any patch differs from one WITH a patch.
cdpm_compute_config_hash("fmt" "1.0.0" "{}" h_nopatch)
assert_ne("${h_after}" "${h_nopatch}" "presence of a patch changes the hash")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: source patches participate in the config hash")
