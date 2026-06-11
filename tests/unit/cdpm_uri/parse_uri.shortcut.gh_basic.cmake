# Test: parse_uri.shortcut.gh_basic
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")
include("${CMAKE_SOURCE_DIR}/tests/helpers.cmake")

cdpm_parse_uri("gh:cdpm-oav/cdpm" PREFIX dep)

assert_eq("${dep_SCHEME_TYPE}"   "GIT_SHORTCUT"                          "scheme type")
assert_eq("${dep_FULL_URI}"      "https://github.com/cdpm-oav/cdpm.git"     "full URI")
assert_eq("${dep_RESOURCE_TYPE}" "GIT_REPO"                              "resource type")
assert_empty("${dep_REF}"                                                 "ref must be empty")
assert_empty("${dep_SUBDIR}"                                              "subdir must be empty")
message(STATUS "PASS: gh: shortcut basic")

