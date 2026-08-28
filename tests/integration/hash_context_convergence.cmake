# Integration: hash_context_convergence
#
# A package installed by the CLI and then consumed through the provider must
# occupy exactly one store slot. Hash convergence between orchestrator and
# provider eliminates duplicate builds for the same configuration.
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH __tests_dir)
cmake_path(GET __tests_dir PARENT_PATH __cdpm_root)
set(cdpm_entry "${__cdpm_root}/cdpm.cmake")
set(cdpm_cli "${__cdpm_root}/cdpm-cli.cmake")

set(fixture "${CMAKE_CURRENT_LIST_DIR}/fixtures/greet")
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/hash_context_convergence")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/project")

set(project_dir "${tmp}/project")
set(store "${tmp}/store")
set(consumer_build "${tmp}/consumer-build")

set(gen_args "")
if(DEFINED CMAKE_GENERATOR AND NOT CMAKE_GENERATOR STREQUAL "")
    set(gen_args -G "${CMAKE_GENERATOR}")
endif()

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
file(WRITE "${tmp}/packages.json" [[{
  "version": 1,
  "packages": { "greet": "packages/greet/package.json" }
}]])

set(project_config "${project_dir}/cdpm.json")
file(WRITE "${project_config}"
"{\n"
"  \"allow_source_override\": true,\n"
"  \"repos\": [ { \"kind\": \"file\", \"path\": \"${tmp}/packages.json\" } ],\n"
"  \"packages\": {\n"
"    \"greet\": {\n"
"      \"source_override\": { \"type\": \"local\", \"path\": \"${fixture}\" }\n"
"    }\n"
"  }\n"
"}\n")

file(WRITE "${project_dir}/CMakeLists.txt"
"cmake_minimum_required(VERSION 3.25)\n"
"project(consumer LANGUAGES CXX)\n"
"find_package(greet REQUIRED CONFIG)\n"
"if(NOT TARGET greet::greet)\n"
"  message(FATAL_ERROR \"greet target missing\")\n"
"endif()\n")

# CLI install. CDPM_STORE_DIR is a script-mode variable and must precede -P.
execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DCDPM_STORE_DIR=${store}" -P "${cdpm_cli}" --
        --project-dir "${project_dir}"
        ${gen_args}
        install greet
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "FAIL: CLI install failed (rc=${rc})\n${out}\n${err}")
endif()

# Consumer configure.
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -S "${project_dir}"
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
    message(FATAL_ERROR "FAIL: consumer configure failed (rc=${rc2})\n${out2}\n${err2}")
endif()

# Exactly one greet slot must exist.
file(GLOB greet_slots LIST_DIRECTORIES true "${store}/greet/*")
set(slot_count 0)
foreach(slot IN LISTS greet_slots)
    if(IS_DIRECTORY "${slot}" AND EXISTS "${slot}/.cdpm_installed")
        math(EXPR slot_count "${slot_count} + 1")
    endif()
endforeach()
assert_eq("${slot_count}" 1 "exactly one greet store slot exists after CLI install + consumer configure")

file(REMOVE_RECURSE "${tmp}" "${consumer_build}")
message(STATUS "PASS: hash_context_convergence")
