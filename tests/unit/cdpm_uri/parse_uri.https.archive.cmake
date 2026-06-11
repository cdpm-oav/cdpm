# Test: parse_uri.https.archive
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")
include("${CMAKE_SOURCE_DIR}/tests/helpers.cmake")

foreach(ext tar.gz tar.bz2 tar.xz tar.zst tgz zip 7z)
    cdpm_parse_uri("https://example.com/pkg-1.0.${ext}" PREFIX dep)
    assert_eq("${dep_SCHEME_TYPE}"   "HTTPS"   "scheme type for .${ext}")
    assert_eq("${dep_RESOURCE_TYPE}" "ARCHIVE" "resource type for .${ext}")
endforeach()
message(STATUS "PASS: https archive extensions -> ARCHIVE")

