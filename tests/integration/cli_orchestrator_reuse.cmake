# Integration: cli_orchestrator_reuse
#
# Invariant: a package built by the CLI install command is reused without any
# store mutation when a consumer project later configures with the same
# generator and toolchain. The orchestrator and the provider must compute the
# same config hash so the consumer takes the sentinel fast-path.
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH __tests_dir)
cmake_path(GET __tests_dir PARENT_PATH __cdpm_root)
set(cdpm_entry "${__cdpm_root}/cdpm.cmake")
set(cdpm_cli "${__cdpm_root}/cdpm-cli.cmake")

set(fixture "${CMAKE_CURRENT_LIST_DIR}/fixtures/greet")
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/cli_orchestrator_reuse")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/project")

set(project_dir "${tmp}/project")
set(store "${tmp}/store")
set(consumer_build "${tmp}/consumer-build")

set(gen_args "")
if(DEFINED CMAKE_GENERATOR AND NOT CMAKE_GENERATOR STREQUAL "")
    set(gen_args -G "${CMAKE_GENERATOR}")
endif()

# Local registry declaring greet.
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

# Consumer lives in the same project directory so it sees the CLI-written lockfile.
file(WRITE "${project_dir}/CMakeLists.txt"
"cmake_minimum_required(VERSION 3.25)\n"
"project(consumer LANGUAGES CXX)\n"
"find_package(greet REQUIRED CONFIG)\n"
"if(NOT TARGET greet::greet)\n"
"  message(FATAL_ERROR \"greet target missing\")\n"
"endif()\n"
"message(STATUS \"consumer: find_package(greet) succeeded\")\n")

# Capture a snapshot of installed package slots and sentinel mtimes.
function(snapshot_store store_dir out_snapshot)
    set(slots "")
    file(GLOB pkg_dirs LIST_DIRECTORIES true "${store_dir}/*")
    foreach(pkg_dir IN LISTS pkg_dirs)
        if(NOT IS_DIRECTORY "${pkg_dir}")
            continue()
        endif()
        cmake_path(GET pkg_dir FILENAME pkg_name)
        file(GLOB hash_dirs LIST_DIRECTORIES true "${pkg_dir}/*")
        foreach(hash_dir IN LISTS hash_dirs)
            if(NOT IS_DIRECTORY "${hash_dir}")
                continue()
            endif()
            cmake_path(GET hash_dir FILENAME hash)
            set(sentinel "${hash_dir}/.cdpm_installed")
            if(EXISTS "${sentinel}")
                file(TIMESTAMP "${sentinel}" mtime)
                list(APPEND slots "${pkg_name}/${hash}:${mtime}")
            endif()
        endforeach()
    endforeach()
    list(SORT slots)
    list(JOIN slots "\n" snapshot)
    set(${out_snapshot} "${snapshot}" PARENT_SCOPE)
endfunction()

snapshot_store("${store}" before_snapshot)
assert_eq("${before_snapshot}" "" "store is empty before CLI install")

# CLI install through the orchestrator. CDPM_STORE_DIR is a script-mode variable
# and must be passed before -P; --project-dir and -G are CLI global options.
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

snapshot_store("${store}" after_cli_snapshot)
assert_ne("${after_cli_snapshot}" "" "CLI install created a store slot")

# Consumer configure with the same generator and toolchain.
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

snapshot_store("${store}" after_consumer_snapshot)
assert_eq("${after_consumer_snapshot}" "${after_cli_snapshot}"
    "consumer configure did not mutate the store (no new slots, no new sentinels, no mtime changes)")

file(REMOVE_RECURSE "${tmp}" "${consumer_build}")
message(STATUS "PASS: cli_orchestrator_reuse")
