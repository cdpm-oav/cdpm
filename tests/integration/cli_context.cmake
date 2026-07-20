# Integration: cli_context
#
# Exercises the real CLI with a project directory separate from its invocation directory. All package
# metadata and sources are local, so the test is deterministic and offline.
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_policy(SET CMP0011 NEW)
cmake_policy(SET CMP0140 NEW)
include(cdpm_context)

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/cli_context")
set(project "${tmp}/project")
set(project2 "${tmp}/project2")
set(invocation "${tmp}/invocation")
set(store "${tmp}/store")
set(fixture "${project}/fixture")
if(DEFINED ENV{TMPDIR})
    set(had_tmpdir TRUE)
    set(saved_tmpdir "$ENV{TMPDIR}")
else()
    set(had_tmpdir FALSE)
endif()
set(ENV{TMPDIR} "${tmp}/system-temp")
set(CDPM_PROJECT_DIR "${project}")
unset(CDPM_RUNTIME_DIR)
_cdpm_resolve_cli_runtime_dir(project_runtime "${store}")
file(REMOVE_RECURSE "${tmp}")
file(REMOVE_RECURSE "${project_runtime}")
file(MAKE_DIRECTORY
    "${project}/registry" "${invocation}" "${fixture}/include" "${project}/locks" "$ENV{TMPDIR}")

file(WRITE "${fixture}/include/greet.hpp" "#pragma once\ninline const char* greet() { return \"hello\"; }\n")
file(WRITE "${fixture}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(greet LANGUAGES NONE)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/build-context.txt"
    "${CMAKE_BUILD_TYPE}|${CDPM_TEST_TOOLCHAIN_MARKER}|${CMAKE_TOOLCHAIN_FILE}\n")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/build-context.txt" DESTINATION ".")
install(DIRECTORY include/ DESTINATION include)
]=])

file(WRITE "${project}/registry/packages.json" [=[
{
  "repo_schema": 1,
  "packages": {
    "greet": {
      "build_system": "cmake",
      "source": { "type": "local", "url": "./fixture" },
      "default_version": "1.0.0",
      "versions": { "1.0.0": {} }
    }
  }
}
]=])
file(WRITE "${project}/cdpm.json" "{\n"
    "  \"cdpm_schema\": 1,\n"
    "  \"store_dir\": \"${store}\",\n"
    "  \"repos\": [ { \"kind\": \"file\", \"path\": \"registry/packages.json\" } ],\n"
    "  \"allow_source_override\": true,\n"
    "  \"packages\": { \"greet\": { \"source_override\": { \"type\": \"local\", "
    "\"path\": \"fixture\" } } }\n"
    "}\n")

function(run_cli project_dir out_var)
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -P "${cdpm_root}/cdpm-cli.cmake" --
            --project-dir "${project_dir}" ${ARGN}
        WORKING_DIRECTORY "${invocation}"
        RESULT_VARIABLE rc
        OUTPUT_VARIABLE stdout
        ERROR_VARIABLE stderr
    )
    set(output "${stdout}${stderr}")
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "FAIL: CLI exited ${rc}\n${output}")
    endif()
    set(${out_var} "${output}")
    return(PROPAGATE ${out_var})
endfunction()

function(run_cli_expect_failure project_dir out_var)
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -P "${cdpm_root}/cdpm-cli.cmake" --
            --project-dir "${project_dir}" ${ARGN}
        WORKING_DIRECTORY "${invocation}"
        RESULT_VARIABLE rc
        OUTPUT_VARIABLE stdout
        ERROR_VARIABLE stderr
    )
    if(rc EQUAL 0)
        message(FATAL_ERROR "FAIL: CLI unexpectedly succeeded\n${stdout}${stderr}")
    endif()
    set(${out_var} "${stdout}${stderr}")
    return(PROPAGATE ${out_var})
endfunction()

function(read_lock_hash lock_path out_var)
    file(READ "${lock_path}" lock_json)
    string(JSON hash GET "${lock_json}" "packages" "greet" "config_hash")
    set(${out_var} "${hash}")
    return(PROPAGATE ${out_var})
endfunction()

# Default build type is Release. The lock hash names both the store slot and its generated wrapper.
run_cli("${project}" release_output install greet)
set(lockfile "${project}/cdpm.lock.json")
if(NOT EXISTS "${lockfile}")
    message(FATAL_ERROR "FAIL: default lockfile was not created under the project directory")
endif()
read_lock_hash("${lockfile}" release_hash)
set(release_install "${store}/greet/${release_hash}")
set(wrapper "${project_runtime}/toolchain/${release_hash}.cmake")
if(NOT EXISTS "${wrapper}")
    message(FATAL_ERROR "FAIL: wrapper was not created under the project-scoped runtime directory")
endif()
file(READ "${wrapper}" wrapper_content)
assert_match("${wrapper_content}" "CMAKE_BUILD_TYPE \"Release\"" "Release reaches the wrapper")
file(READ "${release_install}/build-context.txt" child_context)
assert_match("${child_context}" "^Release\\|\\|${project_runtime}/toolchain/${release_hash}\\.cmake"
    "Release and the hash-derived wrapper reach the child build")

cmake_path(IS_PREFIX project "${project_runtime}" NORMALIZE runtime_in_project)
cmake_path(IS_PREFIX invocation "${project_runtime}" NORMALIZE runtime_in_invocation)
if(runtime_in_project OR runtime_in_invocation)
    message(FATAL_ERROR "FAIL: default runtime must be outside project and invocation directories")
endif()
if(EXISTS "${store}/.runtime")
    message(FATAL_ERROR "FAIL: system temporary directory was available but store/.runtime was created")
endif()
if(EXISTS "${project_runtime}/user/greet-${release_hash}.cmake")
    message(FATAL_ERROR "FAIL: generated user file remains after a successful build")
endif()

foreach(unwanted IN ITEMS
        "${project}/.cdpm" "${invocation}/.cdpm" "${project}/.runtime" "${invocation}/.runtime"
        "${invocation}/cdpm.lock.json")
    if(EXISTS "${unwanted}")
        message(FATAL_ERROR "FAIL: unexpected project/invocation artifact: ${unwanted}")
    endif()
endforeach()

# A global-looking token after the command remains positional (the install version here), rather than
# silently changing the global build context.
run_cli_expect_failure("${project}" post_command_global_output install greet --build-type Debug)
assert_match("${post_command_global_output}" "requested version '--build-type'"
    "global options after the command are not extracted")

# An explicit prefix build type participates in the hash and reaches the child.
run_cli("${project}" debug_output --build-type Debug install greet)
read_lock_hash("${lockfile}" debug_hash)
assert_ne("${debug_hash}" "${release_hash}" "Debug creates a distinct configuration hash")
file(READ "${store}/greet/${debug_hash}/build-context.txt" debug_context)
assert_match("${debug_context}" "^Debug\\|" "Debug reaches the child build")

# The real toolchain's content participates in the hash; an unchanged rerun takes the install fast-path.
set(toolchain "${project}/toolchain.cmake")
file(WRITE "${toolchain}"
    "set(CDPM_TEST_TOOLCHAIN_MARKER \"\${CMAKE_CURRENT_LIST_FILE}\" CACHE STRING \"\" FORCE)\n")
run_cli("${project}" toolchain_one_output --toolchain "${toolchain}" install greet)
read_lock_hash("${lockfile}" toolchain_one_hash)
file(READ "${store}/greet/${toolchain_one_hash}/build-context.txt" toolchain_one_context)
assert_match("${toolchain_one_context}" "^Release\\|${toolchain}\\|${project_runtime}/toolchain/"
    "real toolchain and project wrapper reach the child build")

run_cli("${project}" toolchain_repeat_output --toolchain "${toolchain}" install greet)
read_lock_hash("${lockfile}" toolchain_repeat_hash)
assert_eq("${toolchain_repeat_hash}" "${toolchain_one_hash}" "unchanged toolchain preserves the hash")
assert_match("${toolchain_repeat_output}" "already installed -- skipping" "unchanged rerun takes the fast-path")

# Byte-identical toolchains in two projects have distinct root identities because their normalized paths
# differ. Both store slots and project runtime wrappers must coexist.
file(MAKE_DIRECTORY "${project2}")
file(COPY "${project}/" DESTINATION "${project2}")
file(REMOVE "${project2}/cdpm.lock.json")
set(CDPM_PROJECT_DIR "${project2}")
_cdpm_resolve_cli_runtime_dir(project2_runtime "${store}")
file(REMOVE_RECURSE "${project2_runtime}")
file(SHA256 "${project}/toolchain.cmake" project1_toolchain_sha)
file(SHA256 "${project2}/toolchain.cmake" project2_toolchain_sha)
assert_eq("${project2_toolchain_sha}" "${project1_toolchain_sha}" "project toolchains are byte-identical")

run_cli("${project2}" project2_output --toolchain "${project2}/toolchain.cmake" install greet)
read_lock_hash("${project2}/cdpm.lock.json" project2_hash)
assert_ne("${project2_hash}" "${toolchain_one_hash}" "toolchain path participates in config hash")
assert_ne("${project2_runtime}" "${project_runtime}" "shared-store projects have distinct runtimes")
if(NOT EXISTS "${store}/greet/${toolchain_one_hash}/.cdpm_installed")
    message(FATAL_ERROR "FAIL: first project's store slot was unexpectedly removed or reused")
endif()
set(project2_wrapper "${project2_runtime}/toolchain/${project2_hash}.cmake")
file(READ "${store}/greet/${project2_hash}/build-context.txt" project2_context)
assert_match("${project2_context}"
    "^Release\\|${project2}/toolchain\\.cmake\\|${project2_runtime}/toolchain/${project2_hash}\\.cmake"
    "second child receives its own toolchain and wrapper")
file(READ "${project2_wrapper}" project2_wrapper_content)
assert_match("${project2_wrapper_content}" "include\\(\"${project2}/toolchain\\.cmake\"\\)"
    "second project wrapper includes its own toolchain")
if(EXISTS "${project2_runtime}/user/greet-${project2_hash}.cmake")
    message(FATAL_ERROR "FAIL: second project's generated user file remains after a successful build")
endif()

file(WRITE "${toolchain}" "set(CDPM_TEST_TOOLCHAIN_MARKER two CACHE STRING \"\" FORCE)\n")
run_cli("${project}" toolchain_two_output --toolchain "${toolchain}" install greet)
read_lock_hash("${lockfile}" toolchain_two_hash)
assert_ne("${toolchain_two_hash}" "${toolchain_one_hash}" "toolchain content change moves the hash")

# An explicit runtime passed to the actual CLI overrides the project-scoped temporary default.
set(explicit_runtime "${tmp}/explicit-runtime")
execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DCDPM_RUNTIME_DIR=${explicit_runtime}"
        -P "${cdpm_root}/cdpm-cli.cmake" -- --project-dir "${project}"
        --build-type MinSizeRel install greet
    WORKING_DIRECTORY "${invocation}"
    RESULT_VARIABLE explicit_rc
    OUTPUT_VARIABLE explicit_out
    ERROR_VARIABLE explicit_err
)
if(NOT explicit_rc EQUAL 0)
    message(FATAL_ERROR "FAIL: explicit-runtime CLI exited ${explicit_rc}\n${explicit_out}${explicit_err}")
endif()
read_lock_hash("${lockfile}" explicit_runtime_hash)
if(NOT EXISTS "${explicit_runtime}/toolchain/${explicit_runtime_hash}.cmake"
        OR NOT EXISTS "${explicit_runtime}/bs/greet-${explicit_runtime_hash}")
    message(FATAL_ERROR "FAIL: explicit runtime did not receive wrapper and build scratch")
endif()
if(EXISTS "${project_runtime}/toolchain/${explicit_runtime_hash}.cmake"
        OR EXISTS "${project_runtime}/bs/greet-${explicit_runtime_hash}")
    message(FATAL_ERROR "FAIL: explicit-runtime build used the default project runtime")
endif()
if(EXISTS "${explicit_runtime}/user/greet-${explicit_runtime_hash}.cmake")
    message(FATAL_ERROR "FAIL: explicit-runtime user file remains after a successful build")
endif()

# Explicit relative provision lockfiles are project-relative, not invocation-relative.
file(COPY_FILE "${lockfile}" "${project}/locks/provision.lock.json")
file(SHA256 "${project}/locks/provision.lock.json" provision_lock_before)
run_cli_expect_failure("${project}" provision_output provision --lockfile locks/provision.lock.json)
assert_match("${provision_output}" "dev:true lock entries" "provision rejects non-reproducible dev locks")
file(SHA256 "${project}/locks/provision.lock.json" provision_lock_after)
assert_eq("${provision_lock_after}" "${provision_lock_before}" "failed verification leaves supplied lock byte-identical")
if(EXISTS "${invocation}/locks/provision.lock.json" OR EXISTS "${invocation}/cdpm.lock.json")
    message(FATAL_ERROR "FAIL: provision created a lockfile under the invocation directory")
endif()

file(REMOVE_RECURSE "${tmp}")
file(REMOVE_RECURSE "${project_runtime}" "${project2_runtime}")
if(had_tmpdir)
    set(ENV{TMPDIR} "${saved_tmpdir}")
else()
    unset(ENV{TMPDIR})
endif()
message(STATUS "PASS: CLI project, runtime, build-type, lockfile, and toolchain context")
