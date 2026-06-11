# Test: parse_uri.register.override_builtin
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")
include("${CMAKE_SOURCE_DIR}/tests/helpers.cmake")

cdpm_register_uri_shortcut("gh" "https://mirror.example.com/{path}.git" OVERRIDE QUIET)

cdpm_parse_uri("gh:org/repo" PREFIX dep)
assert_eq("${dep_FULL_URI}" "https://mirror.example.com/org/repo.git" "builtin override must work")
# Overridden built-in → no longer in builtin list by URL, but SCHEME_TYPE depends on name list
message(STATUS "PASS: built-in scheme can be overridden with OVERRIDE")

