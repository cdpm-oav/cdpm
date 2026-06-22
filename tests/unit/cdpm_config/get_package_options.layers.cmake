# Test: get_package_options.layers
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Option precedence (low -> high):
#   package-level options -> version_options[] by range -> per-version options.
# Inject a merged repo directly (the registry is normally built by cdpm_load_repo).
set(meta [[{
  "options": {
    "FMT_TEST": "OFF",
    "FMT_DOC": "OFF"
  },
  "version_options": [
    {
      "range": "[11.0->)",
      "options": {
        "FMT_DOC": "ON",
        "FMT_FUZZ": "OFF"
      }
    }
  ],
  "versions": {
    "10.2.1": {},
    "11.2.0": {
      "options": {
        "FMT_FUZZ": "ON"
      }
    }
  }
}]])
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "{\"packages\":{\"fmt\":${meta}}}")

# No effective config sections -> avoid pulling stray options.
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "{}")

# 10.2.1: only package-level defaults apply (version_options range starts at 11.0).
cdpm_get_package_options("fmt" "10.2.1" o10)
assert_json_member("${o10}" "FMT_TEST" "OFF" "10.2.1 inherits package default")
assert_json_member("${o10}" "FMT_DOC"  "OFF" "10.2.1 keeps package default FMT_DOC")
string(JSON has_fuzz ERROR_VARIABLE fe TYPE "${o10}" "FMT_FUZZ")
assert_true("${fe}" "10.2.1 has no FMT_FUZZ (range did not match)")

# 11.2.0: package default + version_options ([11.0->)) + per-version override.
cdpm_get_package_options("fmt" "11.2.0" o11)
assert_json_member("${o11}" "FMT_TEST" "OFF" "11.2.0 keeps package default FMT_TEST")
assert_json_member("${o11}" "FMT_DOC"  "ON"  "11.2.0 gets FMT_DOC=ON from version_options")
assert_json_member("${o11}" "FMT_FUZZ" "ON"  "11.2.0 per-version FMT_FUZZ overrides version_options")

set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "")
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "")
message(STATUS "PASS: package/version_options/per-version option precedence")
