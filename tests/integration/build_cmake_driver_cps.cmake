# Integration: build_cmake_driver_cps
#
# End-to-end CPS generation + consumption. The header-only greet fixture is built/installed via
# cdpm_build_dependency with CDPM_GENERATE_CPS=ON and a component declaration, producing a
# lib/cps/greet.cps alongside the usual greetConfig.cmake. The generated .cps is validated, then a
# real find_package(greet CONFIG) is driven against an isolated prefix that contains ONLY the .cps
# (no greetConfig.cmake), proving CMake consumes it natively and creates the greet::greet target.
# No network.
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CDPM_GENERATE_CPS ON)

set(fixture "${CMAKE_CURRENT_LIST_DIR}/fixtures/greet")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/build_cmake_driver_cps")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(CDPM_STORE_DIR "${tmp}/store")
set(CMAKE_BINARY_DIR "${tmp}/bin")
set(CMAKE_BUILD_TYPE "Release")

# Local source override pointing at the fixture (allowed via the flag).
set(eff "{\"allow_source_override\":true,\"packages\":{\"greet\":{\"source_override\":{\"type\":\"local\",\"path\":\"${fixture}\"}}}}")
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "${eff}")

set(meta [[{
    "build_system": "cmake",
    "source": { "type": "local", "path": "ignored" },
    "versions": { "1.0.0": {} },
    "default_components": ["greet"],
    "components": { "greet": { "type": "interface" } }
}]])

set(hash "cps01")
set(install_dir "${CDPM_STORE_DIR}/greet/${hash}")

cdpm_build_dependency("greet" "1.0.0" "${hash}" "${meta}")

# ---- The .cps must be generated at lib/cps/greet.cps and be valid --------------------------------
set(cps_file "${install_dir}/lib/cps/greet.cps")
if(NOT EXISTS "${cps_file}")
    message(FATAL_ERROR "FAIL: .cps was not generated at ${cps_file}")
endif()

file(READ "${cps_file}" cps)
assert_json_member("${cps}" "cps_version" "0.14.1" "cps_version")
assert_json_member("${cps}" "name" "greet" "name")
assert_json_member("${cps}" "version" "1.0.0" "version")
assert_json_member("${cps}" "cps_path" "@prefix@/lib/cps" "cps_path")
string(JSON ctype GET "${cps}" "components" "greet" "type")
assert_eq("${ctype}" "interface" "components.greet.type")
string(JSON incl GET "${cps}" "components" "greet" "includes")
assert_json_eq("${incl}" "[\"@prefix@/include\"]" "components.greet.includes")

# ---- Isolated prefix carrying ONLY the CPS (no *Config.cmake) so consumption is unambiguous ------
# CPS consumption via find_package is native from CMake 4.3. On older CMake, validate generation only.
if(CMAKE_VERSION VERSION_LESS "4.3")
    file(REMOVE_RECURSE "${tmp}")
    message(STATUS "PASS: CPS generated (find_package CPS consumption needs CMake >= 4.3; skipped)")
    return()
endif()

set(prefix "${tmp}/cps-prefix")
file(MAKE_DIRECTORY "${prefix}/lib/cps")
file(COPY "${install_dir}/include" DESTINATION "${prefix}")
file(COPY "${cps_file}" DESTINATION "${prefix}/lib/cps")

set(consumer "${tmp}/consumer")
file(MAKE_DIRECTORY "${consumer}")
file(WRITE "${consumer}/CMakeLists.txt"
"cmake_minimum_required(VERSION 3.25)\n"
"project(cps_consumer LANGUAGES CXX)\n"
"find_package(greet CONFIG REQUIRED)\n"
"if(NOT TARGET greet::greet)\n"
"    message(FATAL_ERROR \"greet::greet target not created from CPS\")\n"
"endif()\n"
"get_target_property(_cfg greet::greet _greet_marker)\n"
"message(STATUS \"greet::greet imported from CPS OK\")\n")

set(gen_args "")
if(DEFINED CMAKE_GENERATOR AND NOT CMAKE_GENERATOR STREQUAL "")
    set(gen_args -G "${CMAKE_GENERATOR}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -S "${consumer}"
        -B "${tmp}/consumer-build"
        ${gen_args}
        "-DCMAKE_PREFIX_PATH=${prefix}"
        "-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "FAIL: consumer could not consume the generated .cps (rc=${rc})\n"
        "--- stdout ---\n${out}\n--- stderr ---\n${err}")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: generated .cps is valid and consumed by find_package -> greet::greet")
