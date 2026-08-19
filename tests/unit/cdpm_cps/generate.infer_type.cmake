# Test: generate.infer_type
# Infer component type from discovered artifacts when no type is declared.
# Covers: static from .a, shared from .so/.dylib.
include(cdpm_cps)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CDPM_GENERATE_CPS ON)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/infer_type")
file(REMOVE_RECURSE "${tmp}")
set(install_dir "${tmp}/store/infer/hash01")
file(MAKE_DIRECTORY "${install_dir}/include")
file(MAKE_DIRECTORY "${install_dir}/lib")
file(TOUCH "${install_dir}/include/infer.hpp")
file(TOUCH "${install_dir}/lib/libfoo.a")
file(TOUCH "${install_dir}/lib/libbar.dylib")

set(meta [[{
    "versions": { "1.0.0": {} },
    "default_components": ["foo", "bar"],
    "components": {
        "foo": {},
        "bar": {}
    }
}]])

cdpm_generate_cps_file("infer" "1.0.0" "${install_dir}" "${meta}")

set(cps_file "${install_dir}/lib/cps/infer.cps")
if(NOT EXISTS "${cps_file}")
    message(FATAL_ERROR "FAIL: .cps was not written to ${cps_file}")
endif()

file(READ "${cps_file}" cps)
string(JSON foo_type GET "${cps}" "components" "foo" "type")
assert_eq("${foo_type}" "static" "components.foo.type inferred from .a")

string(JSON bar_type GET "${cps}" "components" "bar" "type")
assert_eq("${bar_type}" "shared" "components.bar.type inferred from .dylib")

string(JSON foo_loc GET "${cps}" "components" "foo" "location")
assert_eq("${foo_loc}" "@prefix@/lib/libfoo.a" "components.foo.location")

string(JSON bar_loc GET "${cps}" "components" "bar" "location")
assert_eq("${bar_loc}" "@prefix@/lib/libbar.dylib" "components.bar.location")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: type inferred from artifacts: static from .a, shared from .dylib")
