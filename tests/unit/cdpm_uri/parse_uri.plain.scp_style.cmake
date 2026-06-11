# Test: parse_uri.plain.scp_style
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")
include("${CMAKE_SOURCE_DIR}/tests/helpers.cmake")

cdpm_parse_uri("git@github.com:cdpm-oav/cdpm.git" PREFIX dep)

assert_eq("${dep_SCHEME_TYPE}"   "PLAIN"    "scheme type")
assert_eq("${dep_FULL_URI}"      "git@github.com:cdpm-oav/cdpm.git" "full URI")
assert_eq("${dep_RESOURCE_TYPE}" "GIT_REPO" "resource type scp-style")
message(STATUS "PASS: scp-style URI -> PLAIN / GIT_REPO")

cdpm_parse_uri("private-github:cdpm-oav/cdpm.git" PREFIX dep2)

assert_eq("${dep2_SCHEME_TYPE}"   "PLAIN"    "scheme type")
assert_eq("${dep2_FULL_URI}"      "private-github:cdpm-oav/cdpm.git" "full URI")
assert_eq("${dep2_RESOURCE_TYPE}" "GIT_REPO" "resource type scp-style")
message(STATUS "PASS: scp-style URI with replaced user + host -> PLAIN / GIT_REPO")

