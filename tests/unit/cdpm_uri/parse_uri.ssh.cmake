# Test: parse_uri.ssh
include(cdpm_uri)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cdpm_parse_uri("ssh://git@github.com/cdpm-oav/cdpm.git" PREFIX dep)
assert_eq("${dep_SCHEME_TYPE}"   "SSH"      "scheme type ssh://")
assert_eq("${dep_RESOURCE_TYPE}" "GIT_REPO" "resource type ssh://")

cdpm_parse_uri("ssh://private-github/cdpm-oav/cdpm.git" PREFIX dep2)
assert_eq("${dep2_SCHEME_TYPE}"   "SSH"      "scheme type ssh://")
assert_eq("${dep2_RESOURCE_TYPE}" "GIT_REPO" "resource type ssh://")

cdpm_parse_uri("git://github.com/cdpm-oav/cdpm.git" PREFIX dep3)
assert_eq("${dep3_SCHEME_TYPE}"   "SSH"      "scheme type git://")
assert_eq("${dep3_RESOURCE_TYPE}" "GIT_REPO" "resource type git://")
message(STATUS "PASS: ssh:// and git:// -> SSH / GIT_REPO")

