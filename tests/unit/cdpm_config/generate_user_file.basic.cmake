# Test: generate_user_file.basic
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# One include file with set(CDPM_USER_<KEY> ...), CDPM_USER_KEYS and
# CDPM_USER_JSON. All keys (tracked + untracked) are delivered.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/gen_user_basic")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/cdpm.json" [[{"cdpm_schema":1}]])
file(WRITE "${tmp}/cdpm_user.json"
[[{"packages":{"fmt":{"user":{"myorg.fips":{"value":"on"},"myorg.mirror-token":{"value":"s3cr3t","tracked":false}}}}}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "${tmp}/cdpm_user.json")
cdpm_config_load(FORCE)

set(out "${tmp}/fmt-user.cmake")
cdpm_generate_user_file("fmt" "${out}" TRACKED_HASH thash)

set(file_written FALSE)
if(EXISTS "${out}")
    set(file_written TRUE)
endif()
assert_true(file_written "user file written")
file(READ "${out}" gen)
assert_match("${gen}" "set\\(CDPM_USER_MYORG_FIPS \"on\"\\)" "normalized key emitted")
assert_match("${gen}" "CDPM_USER_MYORG_MIRROR_TOKEN \"s3cr3t\"" "untracked secret delivered")
assert_match("${gen}" "CDPM_USER_KEYS" "keys list present")
assert_match("${gen}" "CDPM_USER_JSON" "json blob present")
assert_ne("${thash}" "" "tracked hash returned")

# The generated file must itself be valid CMake.
set(inc "${tmp}/inc.cmake")
file(WRITE  "${inc}" "include(\"${out}\")\n")
file(APPEND "${inc}" "if(NOT CDPM_USER_MYORG_FIPS STREQUAL \"on\")\n")
file(APPEND "${inc}" "  message(FATAL_ERROR bad)\nendif()\n")
execute_process(COMMAND "${CMAKE_COMMAND}" -P "${inc}" RESULT_VARIABLE rc)
assert_eq("${rc}" "0" "generated file is valid, includable CMake")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: generate_user_file emits a valid per-package include")
