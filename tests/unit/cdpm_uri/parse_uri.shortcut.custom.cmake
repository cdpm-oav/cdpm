# Test: parse_uri.shortcut.custom
include(cdpm_uri)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cdpm_register_uri_shortcut("mygit" "https://git.example.com/{path}.git")
cdpm_parse_uri("mygit:team/lib" PREFIX dep)

assert_eq("${dep_SCHEME_TYPE}"   "CUSTOM_SHORTCUT"                    "scheme type")
assert_eq("${dep_FULL_URI}"      "https://git.example.com/team/lib.git" "full URI")
assert_eq("${dep_RESOURCE_TYPE}" "GIT_REPO"                           "resource type")
message(STATUS "PASS: custom shortcut -> CUSTOM_SHORTCUT")

