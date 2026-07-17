# Test: generate.interface_basic
# An interface (header-only) component produces a valid .cps at lib/cps/<name>.cps with
# package metadata + an includes-only component (no location).
include(cdpm_cps)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CDPM_GENERATE_CPS ON)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/interface_basic")
file(REMOVE_RECURSE "${tmp}")
set(install_dir "${tmp}/store/greet/hash01")
file(MAKE_DIRECTORY "${install_dir}/include")
file(TOUCH "${install_dir}/include/greet.hpp")

set(meta [[{
    "version_schema": "simple",
    "versions": { "1.0.0": {} },
    "default_components": ["greet"],
    "components": { "greet": { "type": "interface" } }
}]])

cdpm_generate_cps_file("greet" "1.0.0" "${install_dir}" "${meta}")

set(cps_file "${install_dir}/lib/cps/greet.cps")
if(NOT EXISTS "${cps_file}")
    message(FATAL_ERROR "FAIL: .cps was not written to ${cps_file}")
endif()

file(READ "${cps_file}" cps)
assert_json_member("${cps}" "cps_version" "0.14.1" "cps_version")
assert_json_member("${cps}" "name" "greet" "name")
assert_json_member("${cps}" "version" "1.0.0" "version")
assert_json_member("${cps}" "cps_path" "@prefix@/lib/cps" "cps_path")
assert_json_member("${cps}" "version_schema" "simple" "version_schema")

string(JSON ctype GET "${cps}" "components" "greet" "type")
assert_eq("${ctype}" "interface" "components.greet.type")

string(JSON incl GET "${cps}" "components" "greet" "includes")
assert_json_eq("${incl}" "[\"@prefix@/include\"]" "components.greet.includes")

string(JSON defc GET "${cps}" "default_components")
assert_json_eq("${defc}" "[\"greet\"]" "default_components")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: interface component yields a valid includes-only .cps")
