# Test: generate.compat_requires_platform
# compat_version (from the resolved version spec), requires (from dependencies) and
# platform.kernel/isa (from CMAKE_SYSTEM_NAME/PROCESSOR) are emitted.
include(cdpm_cps)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CDPM_GENERATE_CPS ON)

# Deterministic platform for the assertions.
set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/compat_requires_platform")
file(REMOVE_RECURSE "${tmp}")
set(install_dir "${tmp}/store/bar/hash01")
file(MAKE_DIRECTORY "${install_dir}/include")

set(meta [[{
    "versions": {
        "1.2.0": {
            "compat_version": "1.0.0"
        }
    },
    "dependencies": {
        "baz": { "version": "2.0", "components": ["baz"] }
    },
    "components": { "bar": { "type": "interface" } }
}]])

cdpm_generate_cps_file("bar" "1.2.0" "${install_dir}" "${meta}")

file(READ "${install_dir}/lib/cps/bar.cps" cps)
assert_json_member("${cps}" "compat_version" "1.0.0" "compat_version")

string(JSON dep_ver GET "${cps}" "requires" "baz" "version")
assert_eq("${dep_ver}" "2.0" "requires.baz.version")

string(JSON kernel GET "${cps}" "platform" "kernel")
assert_eq("${kernel}" "linux" "platform.kernel")
string(JSON isa GET "${cps}" "platform" "isa")
assert_eq("${isa}" "x86_64" "platform.isa")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: compat_version, requires and platform are emitted")
