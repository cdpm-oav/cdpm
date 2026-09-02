# Test: get_members.bulk
include(cdpm_json)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(entry [[{"version":"1.2.3","config_hash":"abc","install_dir":"/opt/x"}]])

_cdpm_json_get_members(m "${entry}" KEYS version config_hash install_dir
    REQUIRED NON_EMPTY EXPECT_TYPE STRING CONTEXT "record"
)
assert_eq("${m_version}" "1.2.3" "member version")
assert_eq("${m_config_hash}" "abc" "member config_hash")
assert_eq("${m_install_dir}" "/opt/x" "member install_dir")
assert_eq("${m_version_type}" "STRING" "member type captured")

message(STATUS "PASS: json get_members bulk fetch")
