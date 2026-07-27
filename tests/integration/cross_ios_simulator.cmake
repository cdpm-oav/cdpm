# Integration: cross_ios_simulator
#
# End-to-end cross-compilation test: a synthetic Apple iOS Simulator arm64 toolchain
# is supplied via CMAKE_TOOLCHAIN_FILE, then a simple target package is built through
# cdpm_build_dependency. The resulting static library is verified with file(1) and
# otool(1) to be a Mach-O arm64 iOS Simulator binary.
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/cross_ios_simulator")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/source" "${tmp}/store" "${tmp}/runtime")

set(CDPM_STORE_DIR "${tmp}/store")
set(CDPM_RUNTIME_DIR "${tmp}/runtime")

# ---- Synthetic iOS Simulator arm64 toolchain ----------------------------------
set(toolchain "${tmp}/ios-simulator-arm64.cmake")
file(WRITE "${toolchain}" [=[
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_SYSROOT iphonesimulator)
set(CMAKE_OSX_ARCHITECTURES arm64)
]=])
set(CMAKE_TOOLCHAIN_FILE "${toolchain}")
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG [[{"packages":{},"options":{},"user":{}}]])

# ---- Simple target package: static C library -----------------------------------
file(WRITE "${tmp}/source/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(target_pkg C)
add_library(target_pkg STATIC target_pkg.c)
install(TARGETS target_pkg ARCHIVE DESTINATION lib)
]=])
file(WRITE "${tmp}/source/target_pkg.c" [=[
int target_pkg_answer(void) { return 42; }
]=])

# Build metadata with an absolute source path because no project directory is set.
set(meta "{")
string(APPEND meta "\n    \"build_system\": \"cmake\",")
string(APPEND meta "\n    \"source\": { \"type\": \"local\", \"path\": \"${tmp}/source\" },")
string(APPEND meta "\n    \"versions\": { \"1.0.0\": {} }")
string(APPEND meta "\n}")

# ---- Build the package with the iOS simulator toolchain -------------------------
cdpm_build_dependency(target_pkg 1.0.0 ios_sim_test "${meta}")

set(install_dir "${CDPM_STORE_DIR}/target_pkg/ios_sim_test")
set(lib "${install_dir}/lib/libtarget_pkg.a")
if(NOT EXISTS "${lib}")
    message(FATAL_ERROR "FAIL: static library was not installed at ${lib}")
endif()

# ---- Verify Mach-O arm64 iOS Simulator architecture -----------------------------
find_program(FILE_EXECUTABLE NAMES file)
find_program(OTOOL_EXECUTABLE NAMES otool)
if(NOT FILE_EXECUTABLE)
    message(FATAL_ERROR "FAIL: 'file' utility not found; cannot verify binary type")
endif()
if(NOT OTOOL_EXECUTABLE)
    message(FATAL_ERROR "FAIL: 'otool' utility not found; cannot verify binary type")
endif()

execute_process(COMMAND "${FILE_EXECUTABLE}" "${lib}"
    OUTPUT_VARIABLE file_output OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_VARIABLE file_error RESULT_VARIABLE file_rc)
if(NOT file_rc EQUAL 0)
    message(FATAL_ERROR "FAIL: file(1) failed (rc=${file_rc}): ${file_error}")
endif()
if(NOT file_output MATCHES "current ar archive")
    message(FATAL_ERROR "FAIL: library is not a static archive: ${file_output}")
endif()

execute_process(COMMAND "${OTOOL_EXECUTABLE}" -hv "${lib}"
    OUTPUT_VARIABLE otool_output OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_VARIABLE otool_error RESULT_VARIABLE otool_rc)
if(NOT otool_rc EQUAL 0)
    message(FATAL_ERROR "FAIL: otool -hv failed (rc=${otool_rc}): ${otool_error}")
endif()
if(NOT otool_output MATCHES "ARM64")
    message(FATAL_ERROR "FAIL: otool -hv does not report arm64: ${otool_output}")
endif()

# Verify iOS Simulator platform via the LC_BUILD_VERSION load command.
execute_process(COMMAND "${OTOOL_EXECUTABLE}" -l "${lib}"
    OUTPUT_VARIABLE otool_l_output OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_VARIABLE otool_l_error RESULT_VARIABLE otool_l_rc)
if(NOT otool_l_rc EQUAL 0)
    message(FATAL_ERROR "FAIL: otool -l failed (rc=${otool_l_rc}): ${otool_l_error}")
endif()
# PLATFORM_IOSSIMULATOR is 7; accept any of the common simulator markers.
if(NOT otool_l_output MATCHES "platform 7" AND NOT otool_l_output MATCHES "IOSSIMULATOR")
    message(FATAL_ERROR "FAIL: otool -l does not report iOS Simulator platform: ${otool_l_output}")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cross_ios_simulator")
