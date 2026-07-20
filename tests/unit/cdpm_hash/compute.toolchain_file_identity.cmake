# Test: compute.toolchain_file_identity
cmake_policy(SET CMP0011 NEW)
cmake_policy(SET CMP0140 NEW)

include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/toolchain_file_identity")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/one" "${tmp}/two")
set(first "${tmp}/one/toolchain.cmake")
set(second "${tmp}/two/toolchain.cmake")
file(WRITE "${first}" "set(TEST_TOOLCHAIN_VALUE one)\n")
file(COPY_FILE "${first}" "${second}")

set(CMAKE_TOOLCHAIN_FILE "${first}")
cdpm_compute_config_hash("demo" "1.0.0" "{}" first_hash)
set(CMAKE_TOOLCHAIN_FILE "${second}")
cdpm_compute_config_hash("demo" "1.0.0" "{}" second_hash)
assert_ne("${second_hash}" "${first_hash}" "toolchain path participates in root toolchain identity")

file(WRITE "${second}" "set(TEST_TOOLCHAIN_VALUE two)\n")
cdpm_compute_config_hash("demo" "1.0.0" "{}" changed_content_hash)
assert_ne("${changed_content_hash}" "${second_hash}" "root toolchain content participates in identity")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: root toolchain path and content participate in config hash")
