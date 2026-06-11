# Test: parse_uri.shortcut.case_insensitive
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")
include("${CMAKE_SOURCE_DIR}/tests/helpers.cmake")

cdpm_parse_uri("GH:cdpm-oav/cdpm" PREFIX dep)

assert_eq("${dep_SCHEME_TYPE}" "GIT_SHORTCUT" "scheme type must be lowercased")
assert_eq("${dep_FULL_URI}"    "https://github.com/cdpm-oav/cdpm.git" "full URI")
message(STATUS "PASS: scheme is case-insensitive")

