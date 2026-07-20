# Test: probe.config_and_module
include(cdpm_system_dependencies)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH unit_dir)
cmake_path(GET unit_dir PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)
cmake_path(GET cdpm_root PARENT_PATH workspace_root)
set(tmp "${workspace_root}/.playground/system-dependencies-probe")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY
    "${tmp}/prefix/Foo"
    "${tmp}/modules"
    "${tmp}/artifacts"
    "${tmp}/include/foo/tree"
)
set(CDPM_RUNTIME_DIR "${tmp}/runtime")
set(CMAKE_PREFIX_PATH "${tmp}/prefix")
list(PREPEND CMAKE_MODULE_PATH "${tmp}/modules")
set(CDPM_TOOLCHAIN_VARS CDPM_PROBE_MARKER)
set(CDPM_PROBE_MARKER alpha)

file(WRITE "${tmp}/artifacts/foo.a" "foo-one")
file(WRITE "${tmp}/artifacts/bar.a" "bar-one")
file(WRITE "${tmp}/include/foo/header.h" "header-one")
file(WRITE "${tmp}/include/foo/tree/nested.h" "nested-one")
file(WRITE "${tmp}/prefix/Foo/FooConfig.cmake"
    "set(Foo_VERSION 1.4)\ninclude(\"\${CMAKE_CURRENT_LIST_DIR}/FooTargets.cmake\")\n")
file(WRITE "${tmp}/prefix/Foo/FooTargets.cmake"
    "add_library(Foo::Foo UNKNOWN IMPORTED)\n"
    "set_target_properties(Foo::Foo PROPERTIES\n"
    "  IMPORTED_LOCATION \"${tmp}/artifacts/foo.a\"\n"
    "  INTERFACE_INCLUDE_DIRECTORIES \"${tmp}/include\")\n"
)
file(WRITE "${tmp}/prefix/Foo/FooConfigVersion.cmake"
    "set(PACKAGE_VERSION 1.4)\n"
    "if(PACKAGE_FIND_VERSION VERSION_LESS_EQUAL PACKAGE_VERSION)\n"
    "  set(PACKAGE_VERSION_COMPATIBLE TRUE)\n"
    "endif()\n"
)
file(WRITE "${tmp}/modules/FindBar.cmake"
    "set(Bar_FOUND TRUE)\n"
    "set(BAR_VERSION_STRING 2.1)\n"
    "add_library(Bar::Bar UNKNOWN IMPORTED)\n"
    "set_target_properties(Bar::Bar PROPERTIES\n"
    "  IMPORTED_LOCATION_RELEASE \"${tmp}/artifacts/bar.a\"\n"
    "  INTERFACE_COMPILE_DEFINITIONS \"MARKER=\${CDPM_PROBE_MARKER}\")\n"
)

set(dependencies [=[{
  "Foo":{"mode":"CONFIG","version":"1.0","components":["Core"],"identity_targets":["Foo::Foo"],
    "identity_paths":["foo/header.h","foo/tree"]},
  "Bar":{"mode":"MODULE","identity_targets":["Bar::Bar"]}
}]=])
cdpm_probe_system_dependencies("consumer" "${dependencies}" identities_one)

string(JSON foo_mode GET "${identities_one}" Foo mode)
string(JSON foo_version GET "${identities_one}" Foo found_version)
string(JSON bar_version GET "${identities_one}" Bar found_version)
assert_eq("${foo_mode}" "CONFIG" "CONFIG mode is recorded")
assert_eq("${foo_version}" "1.4" "CONFIG version is discovered")
assert_eq("${bar_version}" "2.1" "MODULE _VERSION_STRING is discovered")
assert_match("${identities_one}" "IMPORTED_LOCATION_RELEASE" "config-specific artifact property is recorded")
string(JSON interface_hash_one GET "${identities_one}" Bar targets Bar::Bar INTERFACE_COMPILE_DEFINITIONS)
string(SHA256 expected_interface_hash "INTERFACE_COMPILE_DEFINITIONS=MARKER=alpha")
assert_eq("${interface_hash_one}" "${expected_interface_hash}" "frozen custom toolchain variable reaches probe")
if(identities_one MATCHES "${tmp}")
    message(FATAL_ERROR "FAIL: identities must not contain artifact or definition paths")
endif()

string(JSON identity_path_hash_one GET "${identities_one}" Foo identity_paths 0)
file(WRITE "${tmp}/include/foo/header.h" "header-two")
cdpm_probe_system_dependencies("consumer" "${dependencies}" identities_header)
string(JSON identity_path_hash_two GET "${identities_header}" Foo identity_paths 0)
assert_ne("${identity_path_hash_one}" "${identity_path_hash_two}" "header content changes identity")

file(APPEND "${tmp}/prefix/Foo/FooTargets.cmake" "# config fragment changed\n")
cdpm_probe_system_dependencies("consumer" "${dependencies}" identities_two)
string(JSON foo_definition_one GET "${identities_header}" Foo definition_sha256)
string(JSON foo_definition_two GET "${identities_two}" Foo definition_sha256)
assert_ne("${foo_definition_one}" "${foo_definition_two}" "CONFIG fragment changes definition identity")

set(CDPM_PROBE_MARKER beta)
cdpm_probe_system_dependencies("consumer" "${dependencies}" identities_three)
string(JSON bar_definition_two GET "${identities_two}" Bar definition_sha256)
string(JSON bar_definition_three GET "${identities_three}" Bar definition_sha256)
string(JSON interface_hash_three GET "${identities_three}" Bar targets Bar::Bar INTERFACE_COMPILE_DEFINITIONS)
assert_eq("${bar_definition_two}" "${bar_definition_three}" "MODULE definition identity remains stable")
assert_ne("${interface_hash_one}" "${interface_hash_three}" "MODULE target interface changes identity")

file(WRITE "${tmp}/artifacts/bar.a" "bar-two")
cdpm_probe_system_dependencies("consumer" "${dependencies}" identities_four)
assert_ne("${identities_three}" "${identities_four}" "artifact changes identity")

if(NOT "${CMAKE_GENERATOR_INSTANCE}" STREQUAL "")
    cdpm_probe_system_dependencies("consumer" "${dependencies}" identities_with_instance)
    assert_json_eq("${identities_with_instance}" "${identities_four}" "available generator instance is forwarded")
endif()

file(GLOB_RECURSE probe_entries LIST_DIRECTORIES TRUE "${tmp}/runtime/system-probe/*")
foreach(probe_entry IN LISTS probe_entries)
    cmake_path(GET probe_entry FILENAME probe_entry_name)
    if(probe_entry_name MATCHES [[^(src|build)$]])
        message(FATAL_ERROR "FAIL: successful probe left source/binary directory '${probe_entry}'")
    endif()
endforeach()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: probe.config_and_module")
