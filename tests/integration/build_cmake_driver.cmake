# Integration: build_cmake_driver
#
# End-to-end smoke test of the cmake build-system driver: a local-source fixture
# project is configured/built/installed into the store via cdpm_build_dependency,
# and the install layout + sentinel + idempotency are asserted. No network.
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(fixture "${CMAKE_CURRENT_LIST_DIR}/fixtures/greet")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/build_cmake_driver")
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
    "source": {
        "type": "local",
        "path": "ignored"
    },
    "versions": {
        "1.0.0": {}
    }
}]])

set(hash "smoke01")
set(install_dir "${CDPM_STORE_DIR}/greet/${hash}")

cdpm_build_dependency("greet" "1.0.0" "${hash}" "${meta}")

# Install layout: header + generated package config + sentinel.
if(NOT EXISTS "${install_dir}/include/greet.hpp")
    message(FATAL_ERROR "FAIL: header was not installed at ${install_dir}/include/greet.hpp")
endif()
if(NOT EXISTS "${install_dir}/.cdpm_installed")
    message(FATAL_ERROR "FAIL: sentinel .cdpm_installed was not written")
endif()
file(GLOB_RECURSE cfg "${install_dir}/greetConfig.cmake")
assert_ne("${cfg}" "" "greetConfig.cmake was installed")

# Idempotency: second call must skip (no rebuild). Sentinel mtime unchanged.
file(TIMESTAMP "${install_dir}/.cdpm_installed" ts1)
cdpm_build_dependency("greet" "1.0.0" "${hash}" "${meta}")
file(TIMESTAMP "${install_dir}/.cdpm_installed" ts2)
assert_eq("${ts1}" "${ts2}" "second build is skipped via the sentinel")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cmake driver builds, installs and is idempotent")
