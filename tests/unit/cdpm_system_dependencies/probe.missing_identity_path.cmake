# Test: probe.missing_identity_path
include(cdpm_system_dependencies)

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH unit_dir)
cmake_path(GET unit_dir PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)
cmake_path(GET cdpm_root PARENT_PATH workspace_root)
set(tmp "${workspace_root}/.playground/system-dependencies-missing-path")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/modules" "${tmp}/artifacts" "${tmp}/include")
set(CDPM_RUNTIME_DIR "${tmp}/runtime")
list(PREPEND CMAKE_MODULE_PATH "${tmp}/modules")

file(WRITE "${tmp}/artifacts/missing.a" "artifact")
file(WRITE "${tmp}/modules/FindMissing.cmake"
    "set(Missing_FOUND TRUE)\n"
    "add_library(Missing::Missing UNKNOWN IMPORTED)\n"
    "set_target_properties(Missing::Missing PROPERTIES\n"
    "  IMPORTED_LOCATION \"${tmp}/artifacts/missing.a\"\n"
    "  INTERFACE_INCLUDE_DIRECTORIES \"${tmp}/include\")\n"
)
set(dependencies
    [[{"Missing":{"mode":"MODULE","identity_targets":["Missing::Missing"],"identity_paths":["missing.h"]}}]])
cdpm_probe_system_dependencies("consumer" "${dependencies}" identities)
