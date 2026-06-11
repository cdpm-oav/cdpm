# Test: parse_uri.https.git_repo
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")
include("${CMAKE_SOURCE_DIR}/tests/helpers.cmake")

cdpm_parse_uri("https://github.com/cdpm-oav/cdpm.git" PREFIX dep)

assert_eq("${dep_SCHEME_TYPE}"   "HTTPS"                                       "scheme type")
assert_eq("${dep_FULL_URI}"      "https://github.com/cdpm-oav/cdpm.git"           "full URI")
assert_eq("${dep_RESOURCE_TYPE}" "GIT_REPO"                                    "resource type")
message(STATUS "PASS: https .git URL -> GIT_REPO")

