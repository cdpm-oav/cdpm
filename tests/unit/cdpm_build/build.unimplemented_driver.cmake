# Test: build.unimplemented_driver  (expected to FAIL via WILL_FAIL)
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# A package declaring a not-yet-implemented build_system (make) must abort
# with a clear FATAL_ERROR once the driver is dispatched.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/unimpl_driver")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/src")
file(WRITE "${tmp}/src/configure" "#!/bin/sh\n")

set(CDPM_STORE_DIR "${tmp}/store")
set(CMAKE_BINARY_DIR "${tmp}/bin")

# Local source so prepare_source/patches/toolchain succeed and dispatch is reached.
set(eff "{\"allow_source_override\":true,\"packages\":{\"demo\":{\"source_override\":{\"type\":\"local\",\"path\":\"${tmp}/src\"}}}}")
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "${eff}")

set(meta [[[{
    "build_system": "make",
    "source": {
        "type": "local",
        "path": "ignored"
    },
    "versions": {
        "1.0.0": {}
    }
}]]])

# This dispatches to cdpm_bs_make_build, which is a stub that FATAL_ERRORs.
cdpm_build_dependency("demo" "1.0.0" "abc123" "${meta}")

message(STATUS "UNREACHABLE: unimplemented driver did not abort")
