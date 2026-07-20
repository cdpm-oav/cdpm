# Test: context overrides are normalized and CLI runtimes are project-scoped.
cmake_policy(SET CMP0011 NEW)
cmake_policy(SET CMP0140 NEW)

include(cdpm_context)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/resolve_overrides")
set(CMAKE_SOURCE_DIR "${tmp}/source")
set(CMAKE_BINARY_DIR "${tmp}/build")
set(CDPM_PROJECT_DIR "../project/./nested/../leaf")
set(CDPM_RUNTIME_DIR "../runtime/./scratch")

_cdpm_resolve_project_dir(project_dir)
_cdpm_resolve_runtime_dir(runtime_dir)
assert_eq("${project_dir}" "${tmp}/project/leaf" "relative project override is normalized")
assert_eq("${runtime_dir}" "${tmp}/runtime/scratch" "relative runtime override is normalized")

_cdpm_resolve_cli_runtime_dir(cli_runtime "${tmp}/store")
assert_eq("${cli_runtime}" "${runtime_dir}" "explicit runtime overrides the CLI project runtime")

unset(CDPM_RUNTIME_DIR)
_cdpm_resolve_cli_runtime_dir(first_project_runtime "${tmp}/store")
set(CDPM_PROJECT_DIR "${tmp}/other-project")
_cdpm_resolve_cli_runtime_dir(second_project_runtime "${tmp}/store")
assert_ne("${first_project_runtime}" "${second_project_runtime}" "CLI runtimes differ between projects")

# With every temporary-directory environment variable absent, the store fallback remains project-scoped.
foreach(env_var IN ITEMS TMPDIR TEMP TMP)
    if(DEFINED ENV{${env_var}})
        set(had_${env_var} TRUE)
        set(saved_${env_var} "$ENV{${env_var}}")
    else()
        set(had_${env_var} FALSE)
    endif()
    unset(ENV{${env_var}})
endforeach()
_cdpm_resolve_cli_runtime_dir(fallback_runtime "${tmp}/store")
string(SHA256 project_hash "${tmp}/other-project")
assert_eq("${fallback_runtime}" "${tmp}/store/.runtime/${project_hash}"
    "CLI runtime falls back under the store when no system temp is available")
foreach(env_var IN ITEMS TMPDIR TEMP TMP)
    if(had_${env_var})
        set(ENV{${env_var}} "${saved_${env_var}}")
    else()
        unset(ENV{${env_var}})
    endif()
endforeach()

message(STATUS "PASS: context overrides and project-scoped CLI runtime")
