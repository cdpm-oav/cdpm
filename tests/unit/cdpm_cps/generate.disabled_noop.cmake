# Test: generate.disabled_noop
# Generation is gated by CDPM_GENERATE_CPS: with it off, no file is written.
include(cdpm_cps)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# cdpm_basics defines CDPM_GENERATE_CPS via cmake_dependent_option (default ON on CMake >= 4.3), so the
# disabled path is exercised by explicitly turning it off.
set(CDPM_GENERATE_CPS OFF)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/disabled_noop")
file(REMOVE_RECURSE "${tmp}")
set(install_dir "${tmp}/store/greet/hash01")
file(MAKE_DIRECTORY "${install_dir}/include")

set(meta [[{
    "versions": { "1.0.0": {} },
    "components": { "greet": { "type": "interface" } }
}]])

cdpm_generate_cps_file("greet" "1.0.0" "${install_dir}" "${meta}")

if(EXISTS "${install_dir}/lib/cps/greet.cps")
    message(FATAL_ERROR "FAIL: .cps was written despite CDPM_GENERATE_CPS being off")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: no .cps generated when CDPM_GENERATE_CPS is off")
