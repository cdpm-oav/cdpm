# Test: parse_uri.register.override
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")
include("${CMAKE_SOURCE_DIR}/tests/helpers.cmake")

cdpm_register_uri_shortcut("myov" "https://first.example.com/{path}.git")
cdpm_register_uri_shortcut("myov" "https://second.example.com/{path}.git" OVERRIDE QUIET)

cdpm_parse_uri("myov:org/repo" PREFIX dep)
assert_eq("${dep_FULL_URI}" "https://second.example.com/org/repo.git" "OVERRIDE must replace")
message(STATUS "PASS: OVERRIDE QUIET replaces existing shortcut")

