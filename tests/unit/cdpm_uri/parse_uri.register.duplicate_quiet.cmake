# Test: parse_uri.register.duplicate_quiet
include(cdpm_uri)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cdpm_register_uri_shortcut("mysc" "https://first.example.com/{path}.git")
cdpm_register_uri_shortcut("mysc" "https://second.example.com/{path}.git" QUIET)

# First registration must be preserved
cdpm_parse_uri("mysc:org/repo" PREFIX dep)
assert_eq("${dep_FULL_URI}" "https://first.example.com/org/repo.git" "QUIET must not override")
message(STATUS "PASS: duplicate QUIET skips without replacing")

