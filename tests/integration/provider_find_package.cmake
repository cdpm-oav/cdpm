# Integration: provider_find_package
#
# End-to-end test of the cdpm dependency provider through a real find_package() during a
# sub-CMake configure -- no network. A consumer project includes cdpm.cmake (via
# CMAKE_PROJECT_TOP_LEVEL_INCLUDES) and calls find_package(greet REQUIRED CONFIG). The greet
# package is declared in a local registry and resolved through a local source_override that points
# at the in-tree greet fixture, so the provider builds + installs it into a temp store and the
# consumer's find_package finds the generated greetConfig.cmake.
#
# Also exercises the provider fallback for unknown packages: an unknown REQUIRED package is handed
# off to CMake's normal find_package, which produces the standard failure message.
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# cdpm root = parent of the tests dir; the driver runs from there (WORKING_DIRECTORY).
cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH __tests_dir)
cmake_path(GET __tests_dir PARENT_PATH __cdpm_root)
set(cdpm_entry "${__cdpm_root}/cdpm.cmake")

set(fixture "${CMAKE_CURRENT_LIST_DIR}/fixtures/greet")
set(consumer "${CMAKE_CURRENT_LIST_DIR}/fixtures/provider_consumer")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/provider_find_package")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(store "${tmp}/store")
set(consumer_build "${tmp}/consumer-build")

# In script mode CMAKE_GENERATOR is empty; only forward -G when a generator is actually set,
# otherwise let CMake pick the platform default for the sub-configure.
set(gen_args "")
if(DEFINED CMAKE_GENERATOR AND NOT CMAKE_GENERATOR STREQUAL "")
    set(gen_args -G "${CMAKE_GENERATOR}")
endif()

# ---- Local registry declaring greet (git source is a placeholder; never fetched because the
#      consumer config supplies a local source_override that wins). -----------------------------
file(MAKE_DIRECTORY "${tmp}/packages/greet")
file(WRITE "${tmp}/packages/greet/package.json" [[{
  "build_system": "cmake",
  "source": { "type": "git", "url": "https://example.invalid/greet.git" },
  "default_version": "1.0.0",
  "components": { "greet": { "type": "interface" } },
  "default_components": ["greet"],
  "versions": {
    "1.0.0": { "rev": "0000000000000000000000000000000000000000" }
  }
}]])
set(registry "${tmp}/packages.json")
file(WRITE "${registry}" [[{
  "version": 1,
  "packages": {
    "greet": "packages/greet/package.json"
  }
}]])

# ---- Consumer project config (cdpm.json): point at the registry and override greet's source to
#      the local fixture so the build is offline + deterministic. -------------------------------
set(project_config "${tmp}/cdpm.json")
file(WRITE "${project_config}"
"{\n"
"  \"allow_source_override\": true,\n"
"  \"repos\": [ { \"kind\": \"file\", \"path\": \"${registry}\" } ],\n"
"  \"packages\": {\n"
"    \"greet\": {\n"
"      \"source_override\": { \"type\": \"local\", \"path\": \"${fixture}\" }\n"
"    }\n"
"  }\n"
"}\n")

# ---------------------------------------------------------------------------
# Case 1: find_package(greet REQUIRED) resolves through the provider.
# ---------------------------------------------------------------------------
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -S "${consumer}"
        -B "${consumer_build}"
        ${gen_args}
        "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cdpm_entry}"
        "-DCDPM_STORE_DIR=${store}"
        "-DCDPM_PROJECT_CONFIG=${project_config}"
        "-DCMAKE_BUILD_TYPE=Release"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "FAIL: consumer configure failed (rc=${rc})\n--- stdout ---\n${out}\n--- stderr ---\n${err}")
endif()

# The greet package must be installed in the store with a sentinel and a usable config file.
file(GLOB greet_slots LIST_DIRECTORIES true "${store}/greet/*")
assert_ne("${greet_slots}" "" "greet was installed into the store")
list(GET greet_slots 0 greet_slot)
if(NOT EXISTS "${greet_slot}/.cdpm_installed")
    message(FATAL_ERROR "FAIL: greet store slot has no .cdpm_installed sentinel: ${greet_slot}")
endif()
file(GLOB_RECURSE greet_cfg "${greet_slot}/greetConfig.cmake")
assert_ne("${greet_cfg}" "" "greetConfig.cmake was installed by the provider")

# Provider/library mode keeps its historical build-tree runtime default and never adopts the CLI store
# fallback. The generated user file is removed after the successful dependency build.
set(provider_runtime "${consumer_build}/.cdpm")
if(NOT IS_DIRECTORY "${provider_runtime}")
    message(FATAL_ERROR "FAIL: provider runtime is not under the consumer build: ${provider_runtime}")
endif()
if(EXISTS "${store}/.runtime")
    message(FATAL_ERROR "FAIL: provider unexpectedly created CLI runtime under the store")
endif()
file(GLOB provider_user_files "${provider_runtime}/user/*.cmake")
assert_eq("${provider_user_files}" "" "provider removes generated user files after successful builds")

# The provider must have written a lockfile next to the consumer's source with a greet entry whose
# config_hash matches the installed store slot, and dev:true (the fixture uses a local source_override).
set(lockfile "${consumer}/cdpm.lock.json")
set(lock_exists FALSE)
if(EXISTS "${lockfile}")
    set(lock_exists TRUE)
endif()
assert_true("${lock_exists}" "provider wrote cdpm.lock.json")

file(READ "${lockfile}" lock_json)
string(JSON greet_entry GET "${lock_json}" "packages" "greet")
assert_json_member("${greet_entry}" "version" "1.0.0" "lockfile pins greet version")
assert_json_member("${greet_entry}" "dev" "ON" "lockfile marks the source_override build as dev")

cmake_path(GET greet_slot FILENAME slot_hash)
assert_json_member("${greet_entry}" "config_hash" "${slot_hash}"
    "lockfile config_hash matches the installed store slot")

# ---------------------------------------------------------------------------
# Case 2: re-configure is idempotent (sentinel skip -- no rebuild). With the lockfile now present
# and the sentinel in place, the provider takes the lockfile fast-path on this run.
# ---------------------------------------------------------------------------
file(TIMESTAMP "${greet_slot}/.cdpm_installed" ts1)
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -S "${consumer}"
        -B "${consumer_build}"
        ${gen_args}
        "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cdpm_entry}"
        "-DCDPM_STORE_DIR=${store}"
        "-DCDPM_PROJECT_CONFIG=${project_config}"
        "-DCMAKE_BUILD_TYPE=Release"
    RESULT_VARIABLE rc2
    OUTPUT_VARIABLE out2
    ERROR_VARIABLE err2
)
if(NOT rc2 EQUAL 0)
    message(FATAL_ERROR "FAIL: second consumer configure failed (rc=${rc2})\n${out2}\n${err2}")
endif()
file(TIMESTAMP "${greet_slot}/.cdpm_installed" ts2)
assert_eq("${ts1}" "${ts2}" "second configure is idempotent (sentinel unchanged)")

# ---------------------------------------------------------------------------
# Case 3: unknown REQUIRED package falls through to normal find_package and fails with CMake's
# standard message.
# ---------------------------------------------------------------------------
set(unknown_consumer "${tmp}/unknown")
file(MAKE_DIRECTORY "${unknown_consumer}")
file(WRITE "${unknown_consumer}/CMakeLists.txt"
"cmake_minimum_required(VERSION 3.25)\n"
"project(unknown_consumer LANGUAGES CXX)\n"
"find_package(definitely_not_a_real_pkg REQUIRED)\n")

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -S "${unknown_consumer}"
        -B "${tmp}/unknown-build"
        ${gen_args}
        "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cdpm_entry}"
        "-DCDPM_STORE_DIR=${store}"
        "-DCDPM_PROJECT_CONFIG=${project_config}"
    RESULT_VARIABLE rc3
    OUTPUT_VARIABLE out3
    ERROR_VARIABLE err3
)
if(rc3 EQUAL 0)
    message(FATAL_ERROR "FAIL: unknown package configure should have failed.\n${out3}${err3}")
endif()
string(FIND "${err3}${out3}" "CDPM_ALLOW_SYSTEM_PACKAGES" gate_hint)
if(NOT gate_hint EQUAL -1)
    message(FATAL_ERROR "FAIL: unknown package error should not mention the CDPM_ALLOW_SYSTEM_PACKAGES gate.\n${err3}")
endif()
string(FIND "${err3}${out3}" "Could not find a package configuration file provided by" cmake_hint)
if(cmake_hint EQUAL -1)
    message(FATAL_ERROR "FAIL: unknown package error should be CMake's standard find_package message.\n${err3}")
endif()

# A strict provider can materialize a pinned local git registry without recursively asking itself for Git.
find_program(git_executable NAMES git REQUIRED)
set(git_registry "${tmp}/git-registry")
file(MAKE_DIRECTORY "${git_registry}")
    file(WRITE "${git_registry}/packages.json" [[{"version":1,"packages":{}}]])
execute_process(COMMAND "${git_executable}" init -q WORKING_DIRECTORY "${git_registry}"
    COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${git_executable}" add packages.json WORKING_DIRECTORY "${git_registry}"
    COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${git_executable}" -c user.name=cdpm-test -c user.email=cdpm@example.invalid
        commit -q -m baseline
    WORKING_DIRECTORY "${git_registry}" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${git_executable}" rev-parse HEAD WORKING_DIRECTORY "${git_registry}"
    OUTPUT_VARIABLE git_baseline OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
set(git_config "${tmp}/git-cdpm.json")
file(WRITE "${git_config}" "{\"repos\":[{\"kind\":\"git\",\"url\":\"${git_registry}\","
    "\"baseline\":\"${git_baseline}\"}]}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -S "${unknown_consumer}" -B "${tmp}/git-provider-build" ${gen_args}
        "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cdpm_entry}"
        "-DCDPM_STORE_DIR=${tmp}/git-store" "-DCDPM_PROJECT_CONFIG=${git_config}"
    RESULT_VARIABLE git_provider_rc OUTPUT_VARIABLE git_provider_out ERROR_VARIABLE git_provider_err
)
if(git_provider_rc EQUAL 0)
    message(FATAL_ERROR "FAIL: unknown REQUIRED package should still fail after registry materialization.\n"
        "${git_provider_out}${git_provider_err}")
endif()
string(FIND "${git_provider_out}${git_provider_err}" "not found in any loaded" old_fatal)
if(NOT old_fatal EQUAL -1)
    message(FATAL_ERROR "FAIL: provider should not emit the old 'not found in any loaded' fatal message.\n"
        "${git_provider_out}${git_provider_err}")
endif()
if(NOT EXISTS "${tmp}/git-store/repos/${git_baseline}/packages.json")
    message(FATAL_ERROR "FAIL: strict provider did not materialize the pinned local git registry")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm provider resolves find_package end-to-end, is idempotent, and falls back for unknown packages")
