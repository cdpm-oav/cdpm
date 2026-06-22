# Integration: build_cmake_driver_patch
#
# End-to-end smoke test of the cmake driver's patch step: a copy of the greet
# fixture is patched (via ExternalProject PATCH_COMMAND / git apply) before
# configure, and the patched content is verified in the installed header. No network.
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(fixture "${CMAKE_CURRENT_LIST_DIR}/fixtures/greet")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/build_cmake_driver_patch")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

# Work on a private copy so the patch never mutates the shared fixture.
set(src "${tmp}/src")
file(COPY "${fixture}/" DESTINATION "${src}")

# A unified diff that rewrites the greeting string. The context must match the
# committed fixture verbatim (filler line + no space before the brace).
set(patch "${tmp}/0001-greeting.patch")
file(WRITE "${patch}"
"--- a/include/greet.hpp\n+++ b/include/greet.hpp\n@@ -1,3 +1,3 @@\n // Filler header for test\n #pragma once\n-inline const char* greet(){ return \"hello from greet\"; }\n+inline const char* greet(){ return \"patched greeting\"; }\n")

set(CDPM_STORE_DIR "${tmp}/store")
set(CMAKE_BINARY_DIR "${tmp}/bin")
set(CMAKE_BUILD_TYPE "Release")

set(eff "{\"allow_source_override\":true,\"packages\":{\"greet\":{\"source_override\":{\"type\":\"local\",\"path\":\"${src}\"}}}}")
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "${eff}")

set(meta "{\"build_system\":\"cmake\",\"source\":{\"type\":\"local\",\"path\":\"ignored\"},\"versions\":{\"1.0.0\":{\"patches\":[\"${patch}\"]}}}")

set(hash "patch01")
set(install_dir "${CDPM_STORE_DIR}/greet/${hash}")

cdpm_build_dependency("greet" "1.0.0" "${hash}" "${meta}")

if(NOT EXISTS "${install_dir}/include/greet.hpp")
    message(FATAL_ERROR "FAIL: header was not installed")
endif()
file(READ "${install_dir}/include/greet.hpp" header)
assert_match("${header}" "patched greeting" "patch was applied before configure")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cmake driver applies patches via ExternalProject PATCH_COMMAND")
