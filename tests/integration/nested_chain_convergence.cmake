# Integration: nested_chain_convergence
#
# Invariant: on a native build, a managed package A that depends on a managed
# package B occupies exactly one store slot per package. The orchestrator builds
# B first (depth-first), then A's own child build re-resolves B through the
# injected provider - that nested hash must converge with the top-level one, so
# B is skipped instead of being rebuilt into a second slot. A consumer project
# configuring afterwards with the provider must not mutate the store either.
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH __tests_dir)
cmake_path(GET __tests_dir PARENT_PATH __cdpm_root)
set(cdpm_entry "${__cdpm_root}/cdpm.cmake")
set(cdpm_cli "${__cdpm_root}/cdpm-cli.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/nested_chain_convergence")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY
    "${tmp}/sources/apkg"
    "${tmp}/sources/bpkg"
    "${tmp}/registry/packages/apkg"
    "${tmp}/registry/packages/bpkg"
    "${tmp}/project")

set(registry_dir "${tmp}/registry")
set(project_dir "${tmp}/project")
set(store "${tmp}/store")
set(consumer_build "${tmp}/consumer-build")

set(gen_args "")
if(DEFINED CMAKE_GENERATOR AND NOT CMAKE_GENERATOR STREQUAL "")
    set(gen_args -G "${CMAKE_GENERATOR}")
endif()

# bpkg: installs a header plus a trivial Config file.
file(WRITE "${tmp}/sources/bpkg/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(bpkg NONE)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/bpkg.h" "#define BPKG_VALUE 42\n")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/bpkgConfig.cmake" "set(bpkg_FOUND TRUE)\n")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/bpkg.h" DESTINATION include)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/bpkgConfig.cmake"
    DESTINATION lib/cmake/bpkg)
]=])

# apkg: build-time consumer of bpkg via find_package, plus its own Config file.
# The find_package call re-enters the cdpm provider inside the isolated child
# build - this is the depth-2 resolution the convergence invariant exercises.
file(WRITE "${tmp}/sources/apkg/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(apkg NONE)
find_package(bpkg REQUIRED CONFIG)
if(NOT bpkg_FOUND)
    message(FATAL_ERROR "bpkg not found inside apkg build")
endif()
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/apkgConfig.cmake" "set(apkg_FOUND TRUE)\n")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/apkgConfig.cmake"
    DESTINATION lib/cmake/apkg)
]=])

# Registry. Variable expansion is required for the local source paths.
file(WRITE "${registry_dir}/packages/bpkg/package.json" "{")
file(APPEND "${registry_dir}/packages/bpkg/package.json"
    "\n  \"build_system\": \"cmake\","
    "\n  \"find_package_name\": \"bpkg\","
    "\n  \"source\": { \"type\": \"local\", \"url\": \"${tmp}/sources/bpkg\" },"
    "\n  \"default_version\": \"1.0.0\","
    "\n  \"versions\": { \"1.0.0\": {} }"
    "\n}")
file(WRITE "${registry_dir}/packages/apkg/package.json" "{")
file(APPEND "${registry_dir}/packages/apkg/package.json"
    "\n  \"build_system\": \"cmake\","
    "\n  \"find_package_name\": \"apkg\","
    "\n  \"dependencies\": { \"bpkg\": { \"version\": \"1.0.0\" } },"
    "\n  \"source\": { \"type\": \"local\", \"url\": \"${tmp}/sources/apkg\" },"
    "\n  \"default_version\": \"1.0.0\","
    "\n  \"versions\": { \"1.0.0\": {} }"
    "\n}")
file(WRITE "${registry_dir}/packages.json" "{")
file(APPEND "${registry_dir}/packages.json"
    "\n  \"version\": 1,"
    "\n  \"packages\": {"
    "\n    \"apkg\": \"packages/apkg/package.json\","
    "\n    \"bpkg\": \"packages/bpkg/package.json\""
    "\n  }"
    "\n}")

file(WRITE "${project_dir}/cdpm.json" "{\n"
    "  \"repos\": [ { \"kind\": \"file\", \"path\": \"${registry_dir}/packages.json\" } ]\n"
    "}\n")

# Consumer resolves apkg (which pulls bpkg) through the provider.
file(WRITE "${project_dir}/CMakeLists.txt"
"cmake_minimum_required(VERSION 3.25)\n"
"project(consumer LANGUAGES NONE)\n"
"find_package(apkg REQUIRED CONFIG)\n"
"if(NOT apkg_FOUND)\n"
"  message(FATAL_ERROR \"apkg not found\")\n"
"endif()\n"
"message(STATUS \"consumer: find_package(apkg) succeeded\")\n")

# Counts installed store slots for one package; also returns the total number of
# slot directories so partially-written divergent slots are caught as well.
function(count_slots store_dir pkg out_installed out_total)
    set(installed 0)
    set(total 0)
    file(GLOB slot_dirs LIST_DIRECTORIES true "${store_dir}/${pkg}/*")
    foreach(slot IN LISTS slot_dirs)
        if(NOT IS_DIRECTORY "${slot}")
            continue()
        endif()
        math(EXPR total "${total} + 1")
        if(EXISTS "${slot}/.cdpm_installed")
            math(EXPR installed "${installed} + 1")
        endif()
    endforeach()
    set(${out_installed} "${installed}" PARENT_SCOPE)
    set(${out_total} "${total}" PARENT_SCOPE)
endfunction()

# Captures installed package slots and sentinel mtimes.
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

# CLI install of the root package through the orchestrator. CDPM_STORE_DIR is a
# script-mode variable and must be passed before -P; --project-dir and -G are
# CLI global options.
execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DCDPM_STORE_DIR=${store}" -P "${cdpm_cli}" --
        --project-dir "${project_dir}"
        ${gen_args}
        install apkg
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "FAIL: CLI install failed (rc=${rc})\n${out}\n${err}")
endif()

# Exactly one slot per package: a divergent nested hash for bpkg inside apkg's
# build would have created a second slot there.
count_slots("${store}" apkg apkg_installed apkg_total)
count_slots("${store}" bpkg bpkg_installed bpkg_total)
assert_eq("${apkg_installed}" "1" "exactly one installed apkg slot after CLI install")
assert_eq("${apkg_total}" "1" "no extra apkg slot directories after CLI install")
assert_eq("${bpkg_installed}" "1" "exactly one installed bpkg slot after CLI install")
assert_eq("${bpkg_total}" "1" "nested apkg build did not rebuild bpkg into a second slot")

snapshot_store("${store}" after_cli_snapshot)
assert_ne("${after_cli_snapshot}" "" "CLI install created store slots")

# Consumer configure with the provider: same generator, native build.
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -S "${project_dir}"
        -B "${consumer_build}"
        ${gen_args}
        "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cdpm_entry}"
        "-DCDPM_STORE_DIR=${store}"
        "-DCDPM_PROJECT_CONFIG=${project_dir}/cdpm.json"
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
message(STATUS "PASS: nested_chain_convergence")
