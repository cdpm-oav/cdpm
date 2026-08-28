# Integration: host_tool_once
#
# A host-only tool with find_module hints is built once even when it is reached
# both as a transitive host dependency and through a direct find_package. The
# hint variable is set to the built tool path and the target package that uses
# the tool at build time sees the same path.
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH __tests_dir)
cmake_path(GET __tests_dir PARENT_PATH __cdpm_root)
set(cdpm_entry "${__cdpm_root}/cdpm.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/host_tool_once")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY
    "${tmp}/sources/hosttool"
    "${tmp}/sources/targetpkg"
    "${tmp}/registry/packages/hosttool"
    "${tmp}/registry/packages/targetpkg"
    "${tmp}/project")

set(registry_dir "${tmp}/registry")
set(project_dir "${tmp}/project")
set(store "${tmp}/store")
set(consumer_build "${tmp}/consumer-build")

set(gen_args "")
if(DEFINED CMAKE_GENERATOR AND NOT CMAKE_GENERATOR STREQUAL "")
    set(gen_args -G "${CMAKE_GENERATOR}")
endif()

# hosttool: a tiny executable installed into bin/.
file(WRITE "${tmp}/sources/hosttool/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(hosttool NONE)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/hosttool"
    "#!/bin/sh\necho hello from hosttool\n")
file(CHMOD "${CMAKE_CURRENT_BINARY_DIR}/hosttool"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
install(PROGRAMS "${CMAKE_CURRENT_BINARY_DIR}/hosttool" DESTINATION bin)
]=])

# targetpkg: build-time consumer of hosttool, plus a trivial Config file.
file(WRITE "${tmp}/sources/targetpkg/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(targetpkg NONE)
find_program(HOST_TOOL NAMES hosttool REQUIRED)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/used_hosttool.txt" "${HOST_TOOL}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/targetpkgConfig.cmake" "")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/used_hosttool.txt" DESTINATION share)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/targetpkgConfig.cmake"
    DESTINATION lib/cmake/targetpkg)
]=])

# Registry. Variable expansion is required for the local source paths.
file(WRITE "${registry_dir}/packages/hosttool/package.json" "{")
file(APPEND "${registry_dir}/packages/hosttool/package.json"
    "\n  \"build_system\": \"cmake\","
    "\n  \"find_package_name\": \"hosttool\","
    "\n  \"host_only\": true,"
    "\n  \"find_module\": { \"HOSTTOOL_EXECUTABLE\": \"bin/hosttool\" },"
    "\n  \"source\": { \"type\": \"local\", \"url\": \"${tmp}/sources/hosttool\" },"
    "\n  \"default_version\": \"1.0.0\","
    "\n  \"versions\": { \"1.0.0\": {} }"
    "\n}")
file(WRITE "${registry_dir}/packages/targetpkg/package.json" "{")
file(APPEND "${registry_dir}/packages/targetpkg/package.json"
    "\n  \"build_system\": \"cmake\","
    "\n  \"find_package_name\": \"targetpkg\","
    "\n  \"host_dependencies\": { \"hosttool\": { \"version\": \"1.0.0\" } },"
    "\n  \"source\": { \"type\": \"local\", \"url\": \"${tmp}/sources/targetpkg\" },"
    "\n  \"default_version\": \"1.0.0\","
    "\n  \"versions\": { \"1.0.0\": {} }"
    "\n}")
file(WRITE "${registry_dir}/packages.json" "{")
file(APPEND "${registry_dir}/packages.json"
    "\n  \"version\": 1,"
    "\n  \"packages\": {"
    "\n    \"hosttool\": \"packages/hosttool/package.json\","
    "\n    \"targetpkg\": \"packages/targetpkg/package.json\""
    "\n  }"
    "\n}")

file(WRITE "${project_dir}/cdpm.json" "{\n"
    "  \"repos\": [ { \"kind\": \"file\", \"path\": \"${registry_dir}/packages.json\" } ]\n"
    "}\n")

# Consumer resolves targetpkg (which pulls hosttool as a host dep), then resolves
# hosttool directly. Both paths must converge on a single store slot.
file(WRITE "${project_dir}/CMakeLists.txt"
"cmake_minimum_required(VERSION 3.25)\n"
"project(consumer LANGUAGES NONE)\n"
"find_package(targetpkg REQUIRED CONFIG)\n"
"find_package(hosttool)\n"
"if(NOT DEFINED CACHE{HOSTTOOL_EXECUTABLE})\n"
"  message(FATAL_ERROR \"HOSTTOOL_EXECUTABLE hint was not set\")\n"
"endif()\n"
"get_property(_hint CACHE HOSTTOOL_EXECUTABLE PROPERTY VALUE)\n"
"file(WRITE \"\${CMAKE_CURRENT_BINARY_DIR}/hint_path.txt\" \"\${_hint}\")\n")

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -S "${project_dir}"
        -B "${consumer_build}"
        ${gen_args}
        "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cdpm_entry}"
        "-DCDPM_STORE_DIR=${store}"
        "-DCDPM_PROJECT_CONFIG=${project_dir}/cdpm.json"
        "-DCMAKE_BUILD_TYPE=Release"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "FAIL: consumer configure failed (rc=${rc})\n${out}\n${err}")
endif()

# Exactly one hosttool slot.
file(GLOB hosttool_slots LIST_DIRECTORIES true "${store}/hosttool/*")
set(slot_count 0)
foreach(slot IN LISTS hosttool_slots)
    if(IS_DIRECTORY "${slot}" AND EXISTS "${slot}/.cdpm_installed")
        math(EXPR slot_count "${slot_count} + 1")
    endif()
endforeach()
assert_eq("${slot_count}" 1 "exactly one hosttool store slot exists")

# The hint variable points at the built executable in that single slot. The consumer
# runs in a separate CMake process, so the hint must be read from the file it wrote.
list(GET hosttool_slots 0 hosttool_slot)
set(expected_hint "${hosttool_slot}/bin/hosttool")
file(READ "${consumer_build}/hint_path.txt" recorded_hint)
string(STRIP "${recorded_hint}" recorded_hint)
assert_eq("${recorded_hint}" "${expected_hint}"
    "HOSTTOOL_EXECUTABLE hint points at the built hosttool executable")

file(GLOB targetpkg_slots LIST_DIRECTORIES true "${store}/targetpkg/*")
assert_ne("${targetpkg_slots}" "" "targetpkg was installed into the store")

file(REMOVE_RECURSE "${tmp}" "${consumer_build}")
message(STATUS "PASS: host_tool_once")
