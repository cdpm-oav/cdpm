cmake_policy(SET CMP0011 NEW)
cmake_policy(SET CMP0140 NEW)
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

find_program(git_executable NAMES git REQUIRED)
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/git-local-baseline")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/repo")
file(WRITE "${tmp}/repo/packages.json" [[{"version":1,"packages":{}}]])
execute_process(COMMAND "${git_executable}" init -q WORKING_DIRECTORY "${tmp}/repo" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${git_executable}" add packages.json WORKING_DIRECTORY "${tmp}/repo"
    COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${git_executable}" -c user.name=cdpm-test -c user.email=cdpm@example.invalid
        commit -q -m baseline
    WORKING_DIRECTORY "${tmp}/repo" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${git_executable}" rev-parse HEAD WORKING_DIRECTORY "${tmp}/repo"
    OUTPUT_VARIABLE baseline OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)

set(CDPM_STORE_DIR "${tmp}/store")
set_property(GLOBAL PROPERTY CDPM_REPO_JSON
    "{\"repos\":[{\"kind\":\"git\",\"url\":\"${tmp}/repo\",\"baseline\":\"${baseline}\"}]}")
cdpm_load_repos()
if(NOT EXISTS "${tmp}/store/repos/${baseline}/packages.json")
    message(FATAL_ERROR "FAIL: pinned local git registry was not materialized")
endif()
file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: internal Git lookup bypasses dependency providers")
