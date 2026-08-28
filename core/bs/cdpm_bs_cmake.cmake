# cdpm_bs_cmake.cmake - Default CMake build-system driver for cdpm (ExternalProject-based).

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON iteration helpers (_cdpm_json_foreach / _cdpm_json_get).
include(cdpm_utils)

# ExternalProject re-embeds values in bracket arguments through ``cmake_language(EVAL)``. Reject any
# possible closing bracket delimiter before handing a value to it.
function(_cdpm_validate_external_project_value str)
    if(str MATCHES [=[\]=*\]]=])
        message(FATAL_ERROR "[cdpm] cmake driver: ExternalProject value contains an unsupported closing delimiter.")
    endif()
endfunction()

# .. rst:
# ``_cdpm_cmake_quote_argument(<str> <out>)``
#
# Serializes one string as a quoted CMake argument for the generated mini-project. CMake cannot safely
# represent control characters there, so reject them rather than allowing a value to alter its syntax.
function(_cdpm_cmake_quote_argument str out)
    foreach(code RANGE 1 31)
        string(ASCII ${code} control)
        string(FIND "${str}" "${control}" control_index)
        if(NOT control_index EQUAL -1)
            message(FATAL_ERROR "[cdpm] cmake driver: generated argument contains an unsupported control character.")
        endif()
    endforeach()
    string(ASCII 127 control)
    string(FIND "${str}" "${control}" control_index)
    if(NOT control_index EQUAL -1)
        message(FATAL_ERROR "[cdpm] cmake driver: generated argument contains an unsupported control character.")
    endif()
    string(REPLACE "\\" "\\\\" escaped "${str}")
    string(REPLACE "$" "\\$" escaped "${escaped}")
    string(REPLACE "\"" "\\\"" escaped "${escaped}")
    string(REPLACE ";" "\\;" escaped "${escaped}")
    set(${out} "\"${escaped}\"")
    return(PROPAGATE ${out})
endfunction()

# .. rst:
# ``_cdpm_cmake_quote_external_project_value(<str> <out>)``
#
# Serializes source and command values that ExternalProject embeds again in generated scripts.
function(_cdpm_cmake_quote_external_project_value str out)
    _cdpm_validate_external_project_value("${str}")
    foreach(unsupported IN ITEMS "$" ";" "\"")
        string(FIND "${str}" "${unsupported}" unsupported_index)
        if(NOT unsupported_index EQUAL -1)
            message(FATAL_ERROR "[cdpm] cmake driver: ExternalProject value contains an unsupported character.")
        endif()
    endforeach()
    _cdpm_cmake_quote_argument("${str}" quoted)
    set(${out} "${quoted}")
    return(PROPAGATE ${out})
endfunction()

# .. rst:
# ``_cdpm_cmake_quote_cache_argument(<str> <list_separator> <out>)``
#
# Escapes a cache argument for both the mini-project parse and ExternalProject's generated cache script.
function(_cdpm_cmake_quote_cache_argument str list_separator out)
    _cdpm_validate_external_project_value("${str}")
    string(REPLACE "\\" "\\\\" nested "${str}")
    string(REPLACE "$" "\\$" nested "${nested}")
    string(REPLACE "\"" "\\\"" nested "${nested}")
    string(REPLACE ";" "${list_separator}" nested "${nested}")
    _cdpm_cmake_quote_argument("${nested}" quoted)
    set(${out} "${quoted}")
    return(PROPAGATE ${out})
endfunction()

# .. rst:
# ``cdpm_bs_cmake_build(<ctx_json>)``
#
# Configures, builds and installs a CMake-based package in isolation via ``ExternalProject``.
#
# Rather than adding an ``ExternalProject`` target to the consumer's project tree (which would pollute its
# target graph and is impossible in script mode), cdpm generates a *standalone* mini-project that calls
# ``ExternalProject_Add`` and drives it with ``execute_process(cmake -S/-B ...)`` + ``cmake --build``. This
# is the Hunter model: the isolated build sees only the prepared wrapper toolchain and the forwarded cache
# arguments, and the consumer tree is untouched.
#
# ``<ctx_json>`` members:
#
# * ``source`` - object ``{ type, url?, rev?, sha256?, path? }`` (git | url | local) resolved by
#   ``cdpm_prepare_source``; ExternalProject performs the actual download (git clone / URL+hash);
# * ``patches`` - array of absolute patch file paths applied via ``PATCH_COMMAND`` (``git apply``);
# * ``build_dir`` - scratch root for the generated mini-project and the package build tree;
# * ``install_dir`` - install prefix (the store slot);
# * ``options`` - canonical effective options object (forwarded as ``-D<KEY>:STRING=<VAL>``);
# * ``toolchain`` - path to the prepared wrapper toolchain (may be empty);
# * ``build_type`` / ``generator`` / ``prefix_path`` / ``user_file`` - optional, forwarded when set.
#
# Configure/build run through ``execute_process`` with results checked; any non-zero exit is fatal. Pure
# CMake / git only - no shell.
function(cdpm_bs_cmake_build ctx_json)
    string(JSON build_dir   GET "${ctx_json}" "build_dir")
    string(JSON install_dir GET "${ctx_json}" "install_dir")
    string(JSON source      GET "${ctx_json}" "source")
    string(JSON src_type    GET "${source}" "type")
    string(JSON ep_target   GET "${ctx_json}" "ep_target")

    # If a previous "cdpm clean" removed the install directory but left ExternalProject stamps behind,
    # wipe the stamps so the install step actually runs this time.
    _cdpm_invalidate_ep_stamps("${build_dir}" "${install_dir}" "${ep_target}")

    # Optional members default to empty (or "{}" for options) when absent.
    string(JSON options ERROR_VARIABLE e_opts GET "${ctx_json}" "options")
    if(e_opts)
        set(options "{}")
    endif()
    foreach(member toolchain build_type generator prefix_path module_path user_file program_path execution_path archive_cache_dir)
        string(JSON ${member} ERROR_VARIABLE e_member GET "${ctx_json}" "${member}")
        if(e_member)
            set(${member} "")
        endif()
    endforeach()
    if(execution_path STREQUAL "")
        set(execution_path "$ENV{PATH}")
    endif()

    string(JSON patches ERROR_VARIABLE e_patches GET "${ctx_json}" "patches")
    if(e_patches)
        set(patches "[]")
    endif()

    set(ep_root "${build_dir}/_cdpm_ep")
    set(ep_bin "${ep_root}/_build")
    file(MAKE_DIRECTORY "${ep_root}")

    # ---- Download method (git / url / local) ------------------------------------
    set(download_lines "")
    if(src_type STREQUAL "git")
        string(JSON url GET "${source}" "url")
        string(JSON rev GET "${source}" "rev")
        string(LENGTH "${rev}" rev_length)
        if(NOT rev_length EQUAL 40 OR NOT rev MATCHES [[^[0-9A-Fa-f]+$]])
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] cmake driver: git rev must be exactly 40 hex characters.")
        endif()
        _cdpm_cmake_quote_external_project_value("${url}" url_q)
        _cdpm_cmake_quote_argument("${rev}" rev_q)
        set(download_lines "    GIT_REPOSITORY ${url_q}\n    GIT_TAG ${rev_q}")
    elseif(src_type STREQUAL "url")
        string(JSON url GET "${source}" "url")
        string(JSON sha GET "${source}" "sha256")
        string(LENGTH "${sha}" sha_length)
        if(NOT sha_length EQUAL 64 OR NOT sha MATCHES [[^[0-9A-Fa-f]+$]])
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] cmake driver: URL sha256 must be exactly 64 hex characters.")
        endif()
        _cdpm_cmake_quote_external_project_value("${url}" url_q)
        set(download_lines "    URL ${url_q}\n    URL_HASH SHA256=${sha}")
        if(NOT archive_cache_dir STREQUAL "")
            _cdpm_cmake_quote_external_project_value("${archive_cache_dir}" archive_cache_dir_q)
            string(APPEND download_lines "\n    DOWNLOAD_DIR ${archive_cache_dir_q}")
        endif()
    elseif(src_type STREQUAL "local")
        string(JSON path GET "${source}" "path")
        _cdpm_cmake_quote_external_project_value("${path}" path_q)
        set(download_lines "    SOURCE_DIR ${path_q}\n    DOWNLOAD_COMMAND \"\"")
    else()
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] cmake driver: unsupported source type '${src_type}'.")
    endif()

    # ---- Patch step -------------------------------------------------------------
    set(patch_line "")
    string(JSON npatch ERROR_VARIABLE e_np LENGTH "${patches}")
    if(NOT e_np AND npatch GREATER 0)
        find_program(GIT_EXECUTABLE NAMES git)
        if(NOT GIT_EXECUTABLE)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] 'git' not found; required to apply patches.")
        endif()
        _cdpm_cmake_quote_external_project_value("${GIT_EXECUTABLE}" git_q)
        # ``--no-index`` makes ``git apply`` operate purely on the filesystem relative to its working
        # directory (ExternalProject runs PATCH_COMMAND in <SOURCE_DIR>), exactly like ``patch``. Without
        # it, git walks up to any enclosing repository (the cdpm checkout / the consumer's own repo) and
        # resolves the patch paths against that repo's root instead of the isolated source tree, which
        # fails with "patch does not apply". ``--no-index`` keeps the apply self-contained and portable.
        set(patch_cmd "    PATCH_COMMAND")
        math(EXPR last "${npatch} - 1")
        foreach(i RANGE 0 ${last})
            string(JSON p GET "${patches}" ${i})
            _cdpm_cmake_quote_external_project_value("${p}" p_q)
            if(i EQUAL 0)
                string(APPEND patch_cmd " ${git_q} apply --whitespace=nowarn --no-index ${p_q}")
            else()
                string(APPEND patch_cmd "\n        COMMAND ${git_q} apply --whitespace=nowarn --no-index ${p_q}")
            endif()
        endforeach()
        set(patch_line "${patch_cmd}")
    endif()

    # ---- Cache args forwarded to the child configure ----------------------------
    # CMAKE_CACHE_ARGS avoids command-line length limits; LIST_SEPARATOR lets list-valued
    # variables (e.g. CMAKE_PREFIX_PATH) survive as real ``;`` lists in the child.
    # Choose a separator absent from every cache argument so literal separator-like text also survives.
    set(option_keys "")
    string(JSON option_count LENGTH "${options}")
    if(option_count GREATER 0)
        math(EXPR option_last "${option_count} - 1")
        foreach(option_index RANGE 0 ${option_last})
            string(JSON key MEMBER "${options}" ${option_index})
            list(APPEND option_keys "${key}")
        endforeach()
    endif()
    # Provider injection path; derived from the cdpm root cached by cdpm_build.cmake so it stays valid
    # even when the caller's module_path is a multi-entry list.
    set(__inject_file "${__CDPM_BUILD_ROOT}/core/cdpm_provider_inject.cmake")

    set(separator_index 0)
    set(search_separator ON)
    while(search_separator)
        set(list_separator "__CDPM_LIST_SEPARATOR_${separator_index}__")
        set(separator_found FALSE)
        foreach(value IN ITEMS "${install_dir}" "${build_type}" "${toolchain}" "${prefix_path}"
                "${module_path}" "${user_file}" "${program_path}" "${__inject_file}" "${__CDPM_BUILD_ROOT}")
            string(FIND "${value}" "${list_separator}" separator_position)
            if(NOT separator_position EQUAL -1)
                set(separator_found TRUE)
            endif()
        endforeach()
        foreach(key IN LISTS option_keys)
            _cdpm_json_get("${options}" "${key}" value value_type)
            string(FIND "${key}=${value}" "${list_separator}" separator_position)
            if(NOT separator_position EQUAL -1)
                set(separator_found TRUE)
            endif()
        endforeach()
        if(NOT separator_found)
            set(search_separator OFF)
        else()
            math(EXPR separator_index "${separator_index} + 1")
        endif()
    endwhile()

    set(cache_args_block "")
    _cdpm_cmake_quote_cache_argument(
        "-DCMAKE_INSTALL_PREFIX:PATH=${install_dir}" "${list_separator}" cache_arg
    )
    string(APPEND cache_args_block "        ${cache_arg}")
    if(NOT build_type STREQUAL "")
        _cdpm_cmake_quote_cache_argument(
            "-DCMAKE_BUILD_TYPE:STRING=${build_type}" "${list_separator}" cache_arg
        )
        string(APPEND cache_args_block "\n        ${cache_arg}")
    endif()
    if(NOT toolchain STREQUAL "")
        _cdpm_cmake_quote_cache_argument(
            "-DCMAKE_TOOLCHAIN_FILE:FILEPATH=${toolchain}" "${list_separator}" cache_arg
        )
        string(APPEND cache_args_block "\n        ${cache_arg}")
    endif()
    if(NOT prefix_path STREQUAL "")
        _cdpm_cmake_quote_cache_argument(
            "-DCMAKE_PREFIX_PATH:STRING=${prefix_path}" "${list_separator}" cache_arg
        )
        string(APPEND cache_args_block "\n        ${cache_arg}")
    endif()
    if(NOT program_path STREQUAL "")
        _cdpm_cmake_quote_cache_argument(
            "-DCMAKE_PROGRAM_PATH:STRING=${program_path}" "${list_separator}" cache_arg
        )
        string(APPEND cache_args_block "\n        ${cache_arg}")
    endif()
    if(NOT module_path STREQUAL "")
        _cdpm_cmake_quote_cache_argument(
            "-DCMAKE_MODULE_PATH:STRING=${module_path}" "${list_separator}" cache_arg
        )
        string(APPEND cache_args_block "\n        ${cache_arg}")
    endif()
    if(NOT user_file STREQUAL "")
        _cdpm_cmake_quote_cache_argument(
            "-DCDPM_USER_FILE:FILEPATH=${user_file}" "${list_separator}" cache_arg
        )
        string(APPEND cache_args_block "\n        ${cache_arg}")
    endif()

    if(NOT module_path STREQUAL "")
        _cdpm_cmake_quote_cache_argument(
            "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES:FILEPATH=${__inject_file}" "${list_separator}" cache_arg
        )
        string(APPEND cache_args_block "\n        ${cache_arg}")
        _cdpm_cmake_quote_cache_argument(
            "-DCDPM_INJECT_ROOT:PATH=${__CDPM_BUILD_ROOT}" "${list_separator}" cache_arg
        )
        string(APPEND cache_args_block "\n        ${cache_arg}")
    endif()

    # Forward all CDPM_* cache variables to child builds so version overrides
    # and other configuration options are visible to the provider.
    get_cmake_property(__all_cache_vars CACHE_VARIABLES)
    foreach(__cache_var IN LISTS __all_cache_vars)
        if(__cache_var MATCHES "^CDPM_" AND NOT __cache_var MATCHES "^CDPM_PROVIDER_")
            get_property(__cache_val CACHE "${__cache_var}" PROPERTY VALUE)
            if(NOT __cache_val STREQUAL "")
                get_property(__cache_type CACHE "${__cache_var}" PROPERTY TYPE)
                if(__cache_type STREQUAL "")
                    set(__cache_type "STRING")
                endif()
                _cdpm_cmake_quote_cache_argument(
                    "-D${__cache_var}:${__cache_type}=${__cache_val}" "${list_separator}" cache_arg
                )
                string(APPEND cache_args_block "\n        ${cache_arg}")
            endif()
        endif()
    endforeach()

    # Package options -> -D<KEY>:STRING=<VAL>. Booleans normalized to ON/OFF.
    foreach(key IN LISTS option_keys)
        if(NOT key MATCHES [[^[A-Za-z_][A-Za-z0-9_]*$]])
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] cmake driver: option key '${key}' is not a safe CMake cache variable name.")
        endif()
        _cdpm_json_get("${options}" "${key}" val val_type)
        if(val_type STREQUAL "BOOLEAN")
            if(val)
                set(val "ON")
            else()
                set(val "OFF")
            endif()
        endif()
        _cdpm_cmake_quote_cache_argument("-D${key}:STRING=${val}" "${list_separator}" cache_arg)
        string(APPEND cache_args_block "\n        ${cache_arg}")
    endforeach()

    # Native CPS: forward CMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO when available.
    string(JSON pkg_name ERROR_VARIABLE e_name GET "${ctx_json}" "name")
    string(JSON pkg_version ERROR_VARIABLE e_version GET "${ctx_json}" "version")
    string(JSON meta_json ERROR_VARIABLE e_meta GET "${ctx_json}" "meta_json")
    if(NOT e_name AND NOT e_version AND NOT e_meta)
        string(JSON export_name ERROR_VARIABLE e_export GET "${meta_json}" "export_name")
        if(NOT e_export AND NOT export_name STREQUAL ""
           AND CMAKE_VERSION VERSION_GREATER_EQUAL "4.3")
            _cdpm_cmake_quote_cache_argument(
                "-DCMAKE_EXPERIMENTAL_MAPPED_PACKAGE_INFO:STRING=ababa1b5-7099-495f-a9cd-e22d38f274f2"
                "${list_separator}" gate_arg)
            string(APPEND cache_args_block "\n        ${gate_arg}")
            _cdpm_cmake_quote_cache_argument(
                "-DCMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO:STRING=${export_name}:${pkg_name}/l"
                "${list_separator}" cps_arg)
            string(APPEND cache_args_block "\n        ${cps_arg}")
            _cdpm_cmake_quote_cache_argument(
                "-D${export_name}_EXPORT_PACKAGE_INFO_VERSION:STRING=@PROJECT_VERSION@"
                "${list_separator}" ver_arg)
            string(APPEND cache_args_block "\n        ${ver_arg}")
        endif()
    endif()

    # ---- Assemble the mini-project ----------------------------------------------
    set(ml "cmake_minimum_required(VERSION 3.25)")
    string(APPEND ml "\nproject(cdpm_ep NONE)")
    string(APPEND ml "\ninclude(ExternalProject)")
    string(APPEND ml "\nExternalProject_Add(${ep_target}")
    string(APPEND ml "\n${download_lines}")
    if(NOT patch_line STREQUAL "")
        string(APPEND ml "\n${patch_line}")
    endif()
    string(APPEND ml "\n    LIST_SEPARATOR ${list_separator}")
    string(APPEND ml "\n    CMAKE_CACHE_ARGS")
    string(APPEND ml "\n${cache_args_block}")
    string(APPEND ml "\n)")
    string(APPEND ml "\n")
    file(WRITE "${ep_root}/CMakeLists.txt" "${ml}")

    # ---- Configure the mini-project ---------------------------------------------
    set(configure_cmd "${CMAKE_COMMAND}" -S "${ep_root}" -B "${ep_bin}")
    if(NOT generator STREQUAL "")
        list(APPEND configure_cmd -G "${generator}")
    endif()
    if(NOT toolchain STREQUAL "")
        list(APPEND configure_cmd "-DCMAKE_TOOLCHAIN_FILE=${toolchain}")
    endif()

    message(STATUS "[cdpm] cmake/EP: configuring isolated build for ${src_type} source")
    set(configure_process "${CMAKE_COMMAND}" -E env "PATH=${execution_path}" ${configure_cmd})
    execute_process(
        COMMAND ${configure_process}
        RESULT_VARIABLE rc
    )
    if(NOT rc EQUAL 0)
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] cmake/EP configure failed (exit ${rc}).")
    endif()

    # ---- Drive the ExternalProject (download -> patch -> configure -> build -> install) ----
    message(STATUS "[cdpm] cmake/EP: building -> ${install_dir}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env "PATH=${execution_path}"
            "${CMAKE_COMMAND}" --build "${ep_bin}"
        RESULT_VARIABLE rc
    )
    if(NOT rc EQUAL 0)
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] cmake/EP build failed (exit ${rc}) -> ${install_dir}")
    endif()
endfunction()
