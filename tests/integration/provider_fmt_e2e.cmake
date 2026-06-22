# Integration: provider_fmt_e2e  (NETWORK)
#
# Full end-to-end test through the real cdpm-repo registry: a consumer project calls
# find_package(fmt REQUIRED); the cdpm provider clones fmt at the pinned rev, builds + installs it
# into a temp store, and the consumer links fmt::fmt. Requires network + Git and is therefore only
# registered when the test suite is configured with -DCDPM_TEST_NETWORK=ON.
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH __tests_dir)
cmake_path(GET __tests_dir PARENT_PATH __cdpm_root)
set(cdpm_entry "${__cdpm_root}/cdpm.cmake")

# The official registry is the sibling cdpm-repo submodule (workspace root / cdpm-repo).
cmake_path(GET __cdpm_root PARENT_PATH __workspace_root)
set(registry "${__workspace_root}/cdpm-repo/packages.json")
if(NOT EXISTS "${registry}")
    message(FATAL_ERROR "FAIL: registry not found at ${registry} (is the cdpm-repo submodule checked out?)")
endif()

set(consumer "${CMAKE_CURRENT_LIST_DIR}/fixtures/fmt_consumer")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/provider_fmt_e2e")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(store "${tmp}/store")
set(consumer_build "${tmp}/consumer-build")

# In script mode CMAKE_GENERATOR is empty; only forward -G when a generator is actually set.
set(gen_args "")
if(DEFINED CMAKE_GENERATOR AND NOT CMAKE_GENERATOR STREQUAL "")
    set(gen_args -G "${CMAKE_GENERATOR}")
endif()

# Project config: point at the real registry; pin fmt to a known version for a stable build.
set(project_config "${tmp}/cdpm.json")
file(WRITE "${project_config}"
"{\n"
"  \"repos\": [ { \"kind\": \"file\", \"path\": \"${registry}\" } ],\n"
"  \"packages\": { \"fmt\": { \"version\": \"10.2.1\" } }\n"
"}\n")

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
    message(FATAL_ERROR "FAIL: fmt consumer configure failed (rc=${rc})\n--- stdout ---\n${out}\n--- stderr ---\n${err}")
endif()

file(GLOB fmt_slots LIST_DIRECTORIES true "${store}/fmt/*")
assert_ne("${fmt_slots}" "" "fmt was installed into the store")
list(GET fmt_slots 0 fmt_slot)
if(NOT EXISTS "${fmt_slot}/.cdpm_installed")
    message(FATAL_ERROR "FAIL: fmt store slot has no .cdpm_installed sentinel: ${fmt_slot}")
endif()
file(GLOB_RECURSE fmt_cfg "${fmt_slot}/fmt-config.cmake" "${fmt_slot}/fmtConfig.cmake")
assert_ne("${fmt_cfg}" "" "fmt config file was installed by the provider")

# Build the consumer to prove the link against fmt::fmt actually works.
execute_process(
    COMMAND "${CMAKE_COMMAND}" --build "${consumer_build}"
    RESULT_VARIABLE brc
    OUTPUT_VARIABLE bout
    ERROR_VARIABLE berr
)
if(NOT brc EQUAL 0)
    message(FATAL_ERROR "FAIL: building the fmt consumer failed (rc=${brc})\n${bout}\n${berr}")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm provider builds fmt from the real registry and links it end-to-end")
