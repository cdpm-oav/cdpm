# Test: parse_uri.register.missing_path_placeholder
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")

cdpm_register_uri_shortcut("bad" "https://example.com/fixed-url")
message(FATAL_ERROR "FAIL: expected FATAL_ERROR for missing {path}, but got none")

