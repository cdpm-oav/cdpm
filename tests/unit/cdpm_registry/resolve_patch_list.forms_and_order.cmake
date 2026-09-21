# Test: resolve_patch_list.forms_and_order
include(cdpm_registry)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(meta
[[{
  "patches": [
    { "file": "string.patch", "applies_to": "[1.0->3.0)" },
    { "file": "excluded-array.patch", "applies_to": ["2.0"], "exclude": ["2.0"] },
    { "file": "object.patch", "applies_to": { "from": "2.0", "to": "2.1" } }
  ],
  "versions": {
    "2.0": { "patches": ["version.patch"] }
  }
}]]
)

cdpm_resolve_patch_list("${meta}" "2.0" patches)
assert_json_eq("${patches}" [[ ["string.patch", "object.patch", "version.patch"] ]]
    "string, array, object, exclusions, and declaration order")

message(STATUS "PASS: resolve_patch_list handles applies_to forms, exclusions, and order")
