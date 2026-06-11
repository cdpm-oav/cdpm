# Test: parse_uri.shortcut.case_insensitive
include(cdpm_uri)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cdpm_parse_uri("GH:cdpm-oav/cdpm" PREFIX dep)

assert_eq("${dep_SCHEME_TYPE}" "GIT_SHORTCUT" "scheme type must be lowercased")
assert_eq("${dep_FULL_URI}"    "https://github.com/cdpm-oav/cdpm.git" "full URI")
message(STATUS "PASS: scheme is case-insensitive")

