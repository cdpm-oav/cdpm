# Test: probe.symlink_identity_path
include(cdpm_system_dependencies)

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH unit_dir)
cmake_path(GET unit_dir PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)
cmake_path(GET cdpm_root PARENT_PATH workspace_root)
set(tmp "${workspace_root}/.playground/system-dependencies-symlink-path")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/modules" "${tmp}/artifacts" "${tmp}/include/tree")
set(CDPM_RUNTIME_DIR "${tmp}/runtime")
list(PREPEND CMAKE_MODULE_PATH "${tmp}/modules")

file(WRITE "${tmp}/artifacts/symlink.a" "artifact")
file(WRITE "${tmp}/include/real.h" "header")
file(CREATE_LINK "${tmp}/include/real.h" "${tmp}/include/tree/linked.h" SYMBOLIC RESULT link_result)
if(NOT link_result STREQUAL "0")
    message(STATUS "SKIP: symlink creation unsupported: ${link_result}")
    return()
endif()

file(WRITE "${tmp}/modules/FindSymlink.cmake"
    "set(Symlink_FOUND TRUE)\n"
    "add_library(Symlink::Symlink UNKNOWN IMPORTED)\n"
    "set_target_properties(Symlink::Symlink PROPERTIES\n"
    "  IMPORTED_LOCATION \"${tmp}/artifacts/symlink.a\"\n"
    "  INTERFACE_INCLUDE_DIRECTORIES \"${tmp}/include\")\n"
)
set(dependencies
    [[{"Symlink":{"mode":"MODULE","identity_targets":["Symlink::Symlink"],"identity_paths":["tree"]}}]])
cdpm_probe_system_dependencies("consumer" "${dependencies}" identities)
