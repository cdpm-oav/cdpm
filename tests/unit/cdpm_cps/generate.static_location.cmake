# Test: generate.static_location
# A static component gets a discovered, relocatable @prefix@-relative location for the
# installed static library, alongside include dirs.
include(cdpm_cps)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CDPM_GENERATE_CPS ON)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/static_location")
file(REMOVE_RECURSE "${tmp}")
set(install_dir "${tmp}/store/foo/hash01")
file(MAKE_DIRECTORY "${install_dir}/include")
file(MAKE_DIRECTORY "${install_dir}/lib")
file(TOUCH "${install_dir}/include/foo.hpp")
file(TOUCH "${install_dir}/lib/libfoo.a")

# 'foo' has no declared type; the static library artifact must let the generator infer 'static'.
# 'ghost' is explicitly static with no installed library and must be skipped/pruned.
# 'iface' is explicitly interface to keep the explicit-type path covered.
set(meta [[{
    "versions": { "2.1.0": {} },
    "default_components": ["foo", "ghost", "iface"],
    "components": {
        "foo": {},
        "ghost": { "type": "static" },
        "iface": { "type": "interface" }
    }
}]])

cdpm_generate_cps_file("foo" "2.1.0" "${install_dir}" "${meta}")

set(cps_file "${install_dir}/lib/cps/foo.cps")
if(NOT EXISTS "${cps_file}")
    message(FATAL_ERROR "FAIL: .cps was not written to ${cps_file}")
endif()

file(READ "${cps_file}" cps)
string(JSON ctype GET "${cps}" "components" "foo" "type")
assert_eq("${ctype}" "static" "components.foo.type")

string(JSON loc GET "${cps}" "components" "foo" "location")
assert_eq("${loc}" "@prefix@/lib/libfoo.a" "components.foo.location")

string(JSON incl GET "${cps}" "components" "foo" "includes")
assert_json_eq("${incl}" "[\"@prefix@/include\"]" "components.foo.includes")

# A C++ CABI static library must tell consumers to link the C++ runtime.
string(JSON ll GET "${cps}" "components" "foo" "link_languages")
assert_json_eq("${ll}" "[\"cpp\"]" "components.foo.link_languages")

# The library-less 'ghost' static component must not be emitted...
string(JSON ghost ERROR_VARIABLE e_ghost GET "${cps}" "components" "ghost")
assert_true("${e_ghost}" "ghost component (no library) is skipped")

# The explicit interface component must be emitted.
string(JSON iface_type GET "${cps}" "components" "iface" "type")
assert_eq("${iface_type}" "interface" "components.iface.type")

# ...and default_components must be pruned to emitted components only.
string(JSON defc GET "${cps}" "default_components")
assert_json_eq("${defc}" "[\"foo\", \"iface\"]" "default_components pruned to emitted components")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: type inferred from .a; static gets location + link_languages; unlocatable component is skipped and pruned")
