# Test: parse_uri.register.override
include(cdpm_uri)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cdpm_register_uri_shortcut("myov" "https://first.example.com/{path}.git")
cdpm_register_uri_shortcut("myov" "https://second.example.com/{path}.git" OVERRIDE QUIET)

cdpm_parse_uri("myov:org/repo" PREFIX dep)
assert_eq("${dep_FULL_URI}" "https://second.example.com/org/repo.git" "OVERRIDE must replace")
message(STATUS "PASS: OVERRIDE QUIET replaces existing shortcut")

