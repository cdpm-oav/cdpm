# Test: parse_uri.register.duplicate_fatal
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")

# Expects FATAL_ERROR — CTest checks for non-zero exit
cdpm_register_uri_shortcut("mydup" "https://a.example.com/{path}")
cdpm_register_uri_shortcut("mydup" "https://b.example.com/{path}")
message(FATAL_ERROR "FAIL: expected FATAL_ERROR on duplicate registration, but got none")

