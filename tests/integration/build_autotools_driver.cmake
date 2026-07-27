# Integration: build_autotools_driver
#
# End-to-end smoke test of the autotools build-system driver: a local-source mock
# autotools fixture is configured/built/installed into the store via
# cdpm_build_dependency, and the install layout + sentinel + idempotency are
# asserted. No network, no real autotools required — just a shell and make.
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(fixture "${CMAKE_CURRENT_LIST_DIR}/fixtures/tiny_autotools")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/build_autotools_driver")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(CDPM_STORE_DIR "${tmp}/store")
set(CMAKE_BINARY_DIR "${tmp}/bin")
set(CMAKE_BUILD_TYPE "Release")

# Local source override pointing at the fixture (allowed via the flag).
set(eff "{\"allow_source_override\":true,\"packages\":{\"tiny_autotools\":{\"source_override\":{\"type\":\"local\",\"path\":\"${fixture}\"}}}}")
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "${eff}")

set(meta [[{
    "build_system": "autotools",
    "source": {
        "type": "local",
        "path": "ignored"
    },
    "versions": {
        "1.0.0": {}
    }
}]])

set(hash "autotools01")
set(install_dir "${CDPM_STORE_DIR}/tiny_autotools/${hash}")

cdpm_build_dependency("tiny_autotools" "1.0.0" "${hash}" "${meta}")

# Install layout: header + library sentinel + cdpm sentinel.
if(NOT EXISTS "${install_dir}/include/tiny.h")
    message(FATAL_ERROR "FAIL: header was not installed at ${install_dir}/include/tiny.h")
endif()
if(NOT EXISTS "${install_dir}/lib/libtiny.a")
    message(FATAL_ERROR "FAIL: library sentinel was not installed at ${install_dir}/lib/libtiny.a")
endif()
if(NOT EXISTS "${install_dir}/.cdpm_installed")
    message(FATAL_ERROR "FAIL: sentinel .cdpm_installed was not written")
endif()

# Verify header content contains the config define.
file(READ "${install_dir}/include/tiny.h" header)
assert_match("${header}" "TINY_AUTOTOOLS" "header contains TINY_AUTOTOOLS define")

# Idempotency: second call must skip (no rebuild). Sentinel mtime unchanged.
file(TIMESTAMP "${install_dir}/.cdpm_installed" ts1)
cdpm_build_dependency("tiny_autotools" "1.0.0" "${hash}" "${meta}")
file(TIMESTAMP "${install_dir}/.cdpm_installed" ts2)
assert_eq("${ts1}" "${ts2}" "second build is skipped via the sentinel")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: autotools driver builds, installs and is idempotent")
