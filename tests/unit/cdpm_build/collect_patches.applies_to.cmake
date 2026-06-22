# Test: collect_patches.applies_to
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Package-level patches[] are filtered by applies_to/exclude; per-version patches
# always apply and are appended after the package-level matches (declared order).
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/collect_applies")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/range.patch"   "r\n")
file(WRITE "${tmp}/exclude.patch" "e\n")
file(WRITE "${tmp}/perver.patch"  "v\n")

set(meta "{
  \"patches\": [
    { \"file\": \"${tmp}/range.patch\",   \"applies_to\": \"[10.0->12.0)\" },
    { \"file\": \"${tmp}/exclude.patch\", \"applies_to\": \"[10.0->12.0)\", \"exclude\": [\"11.0.0\"] }
  ],
  \"versions\": {
    \"11.0.0\": { \"patches\": [\"${tmp}/perver.patch\"] },
    \"12.0.0\": {}
  }
}")

# 11.0.0: range.patch applies; exclude.patch is excluded; perver.patch always applies.
cdpm_collect_patches("demo" "11.0.0" "${meta}" p11)
string(JSON n11 LENGTH "${p11}")
assert_eq("${n11}" "2" "11.0.0: range + per-version, exclude dropped")
string(JSON p11_0 GET "${p11}" 0)
string(JSON p11_1 GET "${p11}" 1)
assert_eq("${p11_0}" "${tmp}/range.patch"  "package-level first")
assert_eq("${p11_1}" "${tmp}/perver.patch" "per-version appended after")

# 12.0.0: out of [10.0->12.0) so NO package-level patch; no per-version patch either.
cdpm_collect_patches("demo" "12.0.0" "${meta}" p12)
assert_eq("${p12}" "[]" "12.0.0 outside range, no patches")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: collect_patches honors applies_to/exclude and merge order")
