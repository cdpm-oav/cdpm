# Test: url_template.version_underscored
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# {version_underscored} replaces dots with underscores in the version string.
set(meta [[{"source":{"type":"url","url_template":"https://example.com/{version}/boost_{version_underscored}.tar.gz"},
"versions":{"1.86.0":{"sha256":"0000000000000000000000000000000000000000000000000000000000000000"},
"1.73.0":{"sha256":"1111111111111111111111111111111111111111111111111111111111111111"}}}]])

cdpm_get_package_source("boost" "${meta}" "1.86.0" src_186 dev)
assert_json_member("${src_186}" "url" "https://example.com/1.86.0/boost_1_86_0.tar.gz"
    "{version} and {version_underscored} expand together for 1.86.0")
assert_false("${dev}" "repo source is not a dev override")

cdpm_get_package_source("boost" "${meta}" "1.73.0" src_173 dev)
assert_json_member("${src_173}" "url" "https://example.com/1.73.0/boost_1_73_0.tar.gz"
    "{version_underscored} expands correctly for 1.73.0")
assert_false("${dev}" "repo source is not a dev override")

message(STATUS "PASS: url_template expands {version_underscored} correctly")
