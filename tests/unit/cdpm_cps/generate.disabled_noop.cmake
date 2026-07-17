# Test: generate.disabled_noop
# Generation is opt-in: with CDPM_GENERATE_CPS off (default), no file is written.
include(cdpm_cps)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Deliberately do NOT set CDPM_GENERATE_CPS.

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
