# cdpm_context.cmake - Project and runtime directory resolution.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# .. rst:
# ``_cdpm_resolve_project_dir(<out_dir>)``
#
# Returns the normalized project directory. ``CDPM_PROJECT_DIR`` overrides the library default
# ``CMAKE_SOURCE_DIR``; a relative override is interpreted from that default.
function(_cdpm_resolve_project_dir out_dir)
    if(DEFINED CDPM_PROJECT_DIR AND NOT CDPM_PROJECT_DIR STREQUAL "")
        set(dir "${CDPM_PROJECT_DIR}")
    else()
        set(dir "${CMAKE_SOURCE_DIR}")
    endif()
    cmake_path(ABSOLUTE_PATH dir BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" NORMALIZE OUTPUT_VARIABLE dir)
    set(${out_dir} "${dir}")
    return(PROPAGATE ${out_dir})
endfunction()

# .. rst:
# ``_cdpm_resolve_runtime_dir(<out_dir>)``
#
# Returns the normalized scratch directory. ``CDPM_RUNTIME_DIR`` overrides the library default
# ``${CMAKE_BINARY_DIR}/.cdpm``; a relative override is interpreted from ``CMAKE_BINARY_DIR``.
function(_cdpm_resolve_runtime_dir out_dir)
    if(DEFINED CDPM_RUNTIME_DIR AND NOT CDPM_RUNTIME_DIR STREQUAL "")
        set(dir "${CDPM_RUNTIME_DIR}")
    else()
        set(dir "${CMAKE_BINARY_DIR}/.cdpm")
    endif()
    cmake_path(ABSOLUTE_PATH dir BASE_DIRECTORY "${CMAKE_BINARY_DIR}" NORMALIZE OUTPUT_VARIABLE dir)
    set(${out_dir} "${dir}")
    return(PROPAGATE ${out_dir})
endfunction()

# .. rst:
# ``_cdpm_resolve_cli_runtime_dir(<out_dir> <store_dir>)``
#
# Returns the CLI scratch directory. An explicit ``CDPM_RUNTIME_DIR`` wins. Otherwise the directory is
# project-scoped by the SHA-256 of the normalized project path and placed under the system temporary
# directory. ``<store_dir>/.runtime/<project-hash>`` is used only when no temporary directory is available.
function(_cdpm_resolve_cli_runtime_dir out_dir store_dir)
    if(DEFINED CDPM_RUNTIME_DIR AND NOT CDPM_RUNTIME_DIR STREQUAL "")
        _cdpm_resolve_runtime_dir(dir)
        set(${out_dir} "${dir}")
        return(PROPAGATE ${out_dir})
    endif()

    _cdpm_resolve_project_dir(project_dir)
    string(SHA256 project_hash "${project_dir}")

    set(temp_base "")
    foreach(env_var IN ITEMS TMPDIR TEMP TMP)
        if(DEFINED ENV{${env_var}} AND NOT "$ENV{${env_var}}" STREQUAL "")
            set(temp_base "$ENV{${env_var}}")
            break()
        endif()
    endforeach()

    if(NOT temp_base STREQUAL "")
        cmake_path(ABSOLUTE_PATH temp_base NORMALIZE OUTPUT_VARIABLE temp_base)
        set(dir "${temp_base}/cdpm/${project_hash}")
    else()
        set(dir "${store_dir}/.runtime/${project_hash}")
    endif()
    cmake_path(NORMAL_PATH dir OUTPUT_VARIABLE dir)

    set(${out_dir} "${dir}")
    return(PROPAGATE ${out_dir})
endfunction()
