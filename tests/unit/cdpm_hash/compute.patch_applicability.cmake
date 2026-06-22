# Test: compute.patch_applicability
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# A package-level patch scoped by applies_to must perturb the hash only for the
# versions it applies to; a version outside the range hashes as if the patch
# did not exist.
set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/patch_applic")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(patch "${tmp}/0001-fix.patch")
file(WRITE "${patch}" "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n")

set(meta_with "{
  \"patches\": [ { \"file\": \"${patch}\", \"applies_to\": \"[10.0->12.0)\" } ],
  \"versions\": { \"11.0.0\": {}, \"12.0.0\": {} }
}")
set(meta_none "{ \"versions\": { \"11.0.0\": {}, \"12.0.0\": {} } }")

# In-range version: patch applies -> hash differs from the no-patch meta.
cdpm_compute_config_hash("demo" "11.0.0" "${meta_with}" h11_with)
cdpm_compute_config_hash("demo" "11.0.0" "${meta_none}" h11_none)
assert_ne("${h11_with}" "${h11_none}" "11.0.0 in range: patch moves the hash")

# Out-of-range version: patch does NOT apply -> hash equals the no-patch meta.
cdpm_compute_config_hash("demo" "12.0.0" "${meta_with}" h12_with)
cdpm_compute_config_hash("demo" "12.0.0" "${meta_none}" h12_none)
assert_eq("${h12_with}" "${h12_none}" "12.0.0 out of range: patch ignored in hash")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: patch applicability gates the config hash per version")
