# Test: generate.type_contradiction_warning
# When a declared type contradicts the artifact, the generator emits a WARNING and preserves the
# declared type in the generated CPS.
include(cdpm_cps)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CDPM_GENERATE_CPS ON)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/type_contradiction_warning")
file(REMOVE_RECURSE "${tmp}")
set(install_dir "${tmp}/store/contra/hash01")
file(MAKE_DIRECTORY "${install_dir}/lib")
file(TOUCH "${install_dir}/lib/libfoo.a")

# Run the generator in a sub-script so we can capture the WARNING on stderr.
set(runner "${tmp}/runner.cmake")
file(WRITE "${runner}" [=[
list(PREPEND CMAKE_MODULE_PATH "${CDPM_MODULE_PATH}")
include(cdpm_cps)
set(CDPM_GENERATE_CPS ON)
set(meta [[{
    "versions": { "1.0.0": {} },
    "default_components": ["foo"],
    "components": {
        "foo": { "type": "shared" }
    }
}]])
cdpm_generate_cps_file("contra" "1.0.0" "${INSTALL_DIR}" "${meta}")
]=])

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DCDPM_MODULE_PATH=${CMAKE_MODULE_PATH}"
        "-DINSTALL_DIR=${install_dir}"
        -P "${runner}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "FAIL: sub-script failed (rc=${rc})\n--- stdout ---\n${out}\n--- stderr ---\n${err}")
endif()

if(NOT "${err}" MATCHES "Warning")
    message(FATAL_ERROR "FAIL: expected a WARNING for declared/inferred type mismatch, got stderr:\n${err}")
endif()
if(NOT "${err}" MATCHES "shared")
    message(FATAL_ERROR "FAIL: expected warning to mention declared type 'shared', got stderr:\n${err}")
endif()

set(cps_file "${install_dir}/lib/cps/contra.cps")
if(NOT EXISTS "${cps_file}")
    message(FATAL_ERROR "FAIL: .cps was not written to ${cps_file}")
endif()

file(READ "${cps_file}" cps)
string(JSON foo_type GET "${cps}" "components" "foo" "type")
assert_eq("${foo_type}" "shared" "declared type is preserved despite .a artifact")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: type contradiction emits WARNING and preserves declared type")
