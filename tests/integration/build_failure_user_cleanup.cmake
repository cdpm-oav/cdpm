# Integration: build_failure_user_cleanup
#
# A failing isolated child build must remove its generated user file, including untracked secret values.
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/build_failure_user_cleanup")
set(source "${tmp}/source")
set(runtime "${tmp}/runtime")
set(worker "${tmp}/worker.cmake")
set(config_hash "failing-user-context")
set(user_file "${runtime}/user/demo-${config_hash}.cmake")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${source}")

file(WRITE "${source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(failing_dependency LANGUAGES NONE)
message(FATAL_ERROR "intentional child configure failure")
]=])

string(CONCAT effective
    "{\"allow_source_override\":true,\"user\":{"
    "\"example.secret\":{\"value\":\"top-secret\",\"tracked\":false},"
    "\"example.feature\":{\"value\":\"enabled\",\"tracked\":true}},"
    "\"packages\":{\"demo\":{\"source_override\":{\"type\":\"local\","
    "\"path\":\"${source}\"}}}}")
set(meta [=[{
  "build_system": "cmake",
  "source": { "type": "local", "path": "ignored" },
  "versions": { "1.0.0": {} }
}]=])

file(WRITE "${worker}"
    "cmake_policy(SET CMP0011 NEW)\n"
    "cmake_policy(SET CMP0140 NEW)\n"
    "list(PREPEND CMAKE_MODULE_PATH \"${cdpm_root}/core\")\n"
    "include(cdpm_build)\n"
    "set(CDPM_STORE_DIR \"${tmp}/store\")\n"
    "set(CDPM_RUNTIME_DIR \"${runtime}\")\n"
    "set(CMAKE_BINARY_DIR \"${tmp}/binary\")\n"
    "set(CMAKE_BUILD_TYPE Release)\n"
    "set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG [==[${effective}]==])\n"
    "cdpm_build_dependency(demo 1.0.0 ${config_hash} [==[${meta}]==])\n")

execute_process(
    COMMAND "${CMAKE_COMMAND}" -P "${worker}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE stdout
    ERROR_VARIABLE stderr
)
if(rc EQUAL 0)
    message(FATAL_ERROR "FAIL: intentionally failing child build unexpectedly succeeded")
endif()
assert_match("${stdout}${stderr}" "intentional child configure failure" "child configure reached its failure")
if(EXISTS "${user_file}")
    message(FATAL_ERROR "FAIL: generated user file remains after driver failure: ${user_file}")
endif()
if(NOT EXISTS "${runtime}/bs/demo-${config_hash}/_cdpm_ep/CMakeLists.txt")
    message(FATAL_ERROR "FAIL: failing driver did not receive and start the generated context")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: driver failure removes generated tracked and untracked user values")
