# cdpm_bs_cmake.cmake - Default CMake build-system driver for cdpm (ExternalProject-based).

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON iteration helpers (_cdpm_json_foreach / _cdpm_json_get).
include(cdpm_utils)

# .. rst:
# ``_cdpm_ep_quote(<str> <out>)``
#
# Escapes a string for safe embedding inside a double-quoted argument in the generated mini-project
# (backslash and double-quote). Used for paths/URLs written into the ``ExternalProject_Add`` call.
function(_cdpm_ep_quote str out)
    string(REPLACE "\\" "\\\\" str "${str}")
    string(REPLACE "\"" "\\\"" str "${str}")
    set(${out} "${str}")
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

    # Optional members default to empty (or "{}" for options) when absent.
    string(JSON options ERROR_VARIABLE e_opts GET "${ctx_json}" "options")
    if(e_opts)
        set(options "{}")
    endif()
    foreach(member toolchain build_type generator prefix_path user_file)
        string(JSON ${member} ERROR_VARIABLE e_member GET "${ctx_json}" "${member}")
        if(e_member)
            set(${member} "")
        endif()
    endforeach()

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
        _cdpm_ep_quote("${url}" url_q)
        _cdpm_ep_quote("${rev}" rev_q)
        list(APPEND download_lines "    GIT_REPOSITORY \"${url_q}\"" "    GIT_TAG \"${rev_q}\"")
    elseif(src_type STREQUAL "url")
        string(JSON url GET "${source}" "url")
        string(JSON sha GET "${source}" "sha256")
        _cdpm_ep_quote("${url}" url_q)
        list(APPEND download_lines "    URL \"${url_q}\"" "    URL_HASH SHA256=${sha}")
    elseif(src_type STREQUAL "local")
        string(JSON path GET "${source}" "path")
        _cdpm_ep_quote("${path}" path_q)
        list(APPEND download_lines "    SOURCE_DIR \"${path_q}\"" "    DOWNLOAD_COMMAND \"\"")
    else()
        message(FATAL_ERROR "[cdpm] cmake driver: unsupported source type '${src_type}'.")
    endif()

    # ---- Patch step -------------------------------------------------------------
    set(patch_line "")
    string(JSON npatch ERROR_VARIABLE e_np LENGTH "${patches}")
    if(NOT e_np AND npatch GREATER 0)
        find_program(GIT_EXECUTABLE NAMES git)
        if(NOT GIT_EXECUTABLE)
            message(FATAL_ERROR "[cdpm] 'git' not found; required to apply patches.")
        endif()
        _cdpm_ep_quote("${GIT_EXECUTABLE}" git_q)
        # ``--no-index`` makes ``git apply`` operate purely on the filesystem relative to its working
        # directory (ExternalProject runs PATCH_COMMAND in <SOURCE_DIR>), exactly like ``patch``. Without
        # it, git walks up to any enclosing repository (the cdpm checkout / the consumer's own repo) and
        # resolves the patch paths against that repo's root instead of the isolated source tree, which
        # fails with "patch does not apply". ``--no-index`` keeps the apply self-contained and portable.
        set(patch_cmd "    PATCH_COMMAND")
        math(EXPR last "${npatch} - 1")
        foreach(i RANGE 0 ${last})
            string(JSON p GET "${patches}" ${i})
            _cdpm_ep_quote("${p}" p_q)
            if(i EQUAL 0)
                string(APPEND patch_cmd " \"${git_q}\" apply --whitespace=nowarn --no-index \"${p_q}\"")
            else()
                string(APPEND patch_cmd "\n        COMMAND \"${git_q}\" apply --whitespace=nowarn --no-index \"${p_q}\"")
            endif()
        endforeach()
        set(patch_line "${patch_cmd}")
    endif()

    # ---- Cache args forwarded to the child configure ----------------------------
    # CMAKE_CACHE_ARGS avoids command-line length limits; LIST_SEPARATOR lets list-valued
    # variables (e.g. CMAKE_PREFIX_PATH) survive as real ``;`` lists in the child.
    set(cache_args "")
    list(APPEND cache_args "        \"-DCMAKE_INSTALL_PREFIX:PATH=${install_dir}\"")
    if(NOT build_type STREQUAL "")
        list(APPEND cache_args "        \"-DCMAKE_BUILD_TYPE:STRING=${build_type}\"")
    endif()
    if(NOT prefix_path STREQUAL "")
        string(REPLACE ";" "|" prefix_path_alt "${prefix_path}")
        list(APPEND cache_args "        \"-DCMAKE_PREFIX_PATH:STRING=${prefix_path_alt}\"")
    endif()
    if(NOT user_file STREQUAL "")
        list(APPEND cache_args "        \"-DCDPM_USER_FILE:FILEPATH=${user_file}\"")
    endif()

    # Package options -> -D<KEY>:STRING=<VAL>. Booleans normalized to ON/OFF.
    _cdpm_json_foreach("${options}" opt_keys)
    foreach(key IN LISTS opt_keys)
        _cdpm_json_get("${options}" "${key}" val val_type)
        if(val_type STREQUAL "BOOLEAN")
            if(val)
                set(val "ON")
            else()
                set(val "OFF")
            endif()
        endif()
        list(APPEND cache_args "        \"-D${key}:STRING=${val}\"")
    endforeach()
    list(JOIN cache_args "\n" cache_args_block)

    # ---- Assemble the mini-project ----------------------------------------------
    list(JOIN download_lines "\n" download_block)

    set(ml "cmake_minimum_required(VERSION 3.25)")
    string(APPEND ml "\nproject(cdpm_ep NONE)")
    string(APPEND ml "\ninclude(ExternalProject)")
    string(APPEND ml "\nExternalProject_Add(cdpm_pkg")
    string(APPEND ml "\n${download_block}")
    if(NOT patch_line STREQUAL "")
        string(APPEND ml "\n${patch_line}")
    endif()
    string(APPEND ml "\n    LIST_SEPARATOR |")
    string(APPEND ml "\n    CMAKE_CACHE_ARGS")
    string(APPEND ml "\n${cache_args_block}")
    string(APPEND ml "\n    # TODO(cdpm): forward CMAKE_PROJECT_TOP_LEVEL_INCLUDES to re-inject the provider")
    string(APPEND ml "\n    #             so the child build can resolve its own transitive find_package().")
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
    execute_process(
        COMMAND ${configure_cmd}
        RESULT_VARIABLE rc
    )
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "[cdpm] cmake/EP configure failed (exit ${rc}).")
    endif()

    # ---- Drive the ExternalProject (download -> patch -> configure -> build -> install) ----
    message(STATUS "[cdpm] cmake/EP: building -> ${install_dir}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" --build "${ep_bin}"
        RESULT_VARIABLE rc
    )
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "[cdpm] cmake/EP build failed (exit ${rc}) -> ${install_dir}")
    endif()
endfunction()
