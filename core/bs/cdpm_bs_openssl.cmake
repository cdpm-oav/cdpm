# cdpm_bs_openssl.cmake - OpenSSL build-system driver for cdpm (perl Configure + make/nmake via ExternalProject).

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON iteration helpers.
include(cdpm_utils)

# ExternalProject re-embeds values in bracket arguments through ``cmake_language(EVAL)``. Reject any
# possible closing bracket delimiter before handing a value to it.
function(_cdpm_openssl_validate_external_project_value str)
    if(str MATCHES [=[\]=*\]]=])
        message(FATAL_ERROR "[cdpm] openssl driver: ExternalProject value contains an unsupported closing delimiter.")
    endif()
endfunction()

# .. rst:
# ``_cdpm_openssl_quote_argument(<str> <out>)``
#
# Serializes one string as a quoted CMake argument for the generated mini-project. CMake cannot safely
# represent control characters there, so reject them rather than allowing a value to alter its syntax.
function(_cdpm_openssl_quote_argument str out)
    foreach(code RANGE 1 31)
        string(ASCII ${code} control)
        string(FIND "${str}" "${control}" control_index)
        if(NOT control_index EQUAL -1)
            message(FATAL_ERROR "[cdpm] openssl driver: generated argument contains an unsupported control character.")
        endif()
    endforeach()
    string(ASCII 127 control)
    string(FIND "${str}" "${control}" control_index)
    if(NOT control_index EQUAL -1)
        message(FATAL_ERROR "[cdpm] openssl driver: generated argument contains an unsupported control character.")
    endif()
    string(REPLACE "\\" "\\\\" escaped "${str}")
    string(REPLACE "$" "\\$" escaped "${escaped}")
    string(REPLACE "\"" "\\\"" escaped "${escaped}")
    string(REPLACE ";" "\\;" escaped "${escaped}")
    set(${out} "\"${escaped}\"")
    return(PROPAGATE ${out})
endfunction()

# .. rst:
# ``_cdpm_openssl_quote_external_project_value(<str> <out>)``
#
# Serializes source and command values that ExternalProject embeds again in generated scripts.
function(_cdpm_openssl_quote_external_project_value str out)
    _cdpm_openssl_validate_external_project_value("${str}")
    foreach(unsupported IN ITEMS "$" ";" "\"")
        string(FIND "${str}" "${unsupported}" unsupported_index)
        if(NOT unsupported_index EQUAL -1)
            message(FATAL_ERROR "[cdpm] openssl driver: ExternalProject value contains an unsupported character.")
        endif()
    endforeach()
    _cdpm_openssl_quote_argument("${str}" quoted)
    set(${out} "${quoted}")
    return(PROPAGATE ${out})
endfunction()

# .. rst:
# ``_cdpm_openssl_configure_target(<ctx_json> <out_target>)``
#
# Selects the OpenSSL Configure target for the current host platform from
# ``ctx_json.build.configure_target_map``.
function(_cdpm_openssl_configure_target ctx_json out_target)
    string(JSON target_map ERROR_VARIABLE err GET "${ctx_json}" "build" "configure_target_map")
    if(err)
        set(${out_target} "")
        return(PROPAGATE ${out_target})
    endif()

    _cdpm_get_host_processor(host_proc)
    set(platform_key "${CMAKE_HOST_SYSTEM_NAME}-${host_proc}")
    string(JSON target ERROR_VARIABLE target_err GET "${target_map}" "${platform_key}")
    if(target_err)
        set(${out_target} "")
        return(PROPAGATE ${out_target})
    endif()

    set(${out_target} "${target}")
    return(PROPAGATE ${out_target})
endfunction()

# .. rst:
# ``_cdpm_openssl_configure_args(<ctx_json> <out_args>)``
#
# Builds the list of Configure arguments. Defaults ``no-shared`` and ``no-tests`` are appended first;
# package options from ``ctx_json.options`` follow so they can override defaults.
function(_cdpm_openssl_configure_args ctx_json out_args)
    set(args "")
    list(APPEND args "no-shared" "no-tests")

    string(JSON options ERROR_VARIABLE err GET "${ctx_json}" "options")
    if(NOT err)
        set(option_keys "")
        _cdpm_json_foreach("${options}" option_keys)
        foreach(key IN LISTS option_keys)
            _cdpm_json_get("${options}" "${key}" val val_type)
            string(TOLOWER "${key}" flag)
            string(REPLACE "_" "-" flag "${flag}")
            if(val_type STREQUAL "BOOLEAN")
                if(val)
                    list(APPEND args "${flag}")
                endif()
            elseif(val_type STREQUAL "STRING")
                if(val STREQUAL "")
                    list(APPEND args "${flag}")
                else()
                    list(APPEND args "${flag}=${val}")
                endif()
            else()
                list(APPEND args "${flag}=${val}")
            endif()
        endforeach()
    endif()

    set(${out_args} "${args}")
    return(PROPAGATE ${out_args})
endfunction()

# .. rst:
# ``cdpm_bs_openssl_build(<ctx_json>)``
#
# Builds and installs an OpenSSL package in isolation via ``ExternalProject``. A standalone mini-project
# calls ``ExternalProject_Add`` with custom ``CONFIGURE_COMMAND`` (``perl Configure``), ``BUILD_COMMAND``
# (``make``/``nmake``) and ``INSTALL_COMMAND`` (``make install_sw``/``nmake install_sw``). The mini-project
# is then driven with ``execute_process(cmake -S/-B ...)`` + ``cmake --build``, exactly like the cmake
# driver.
#
# ``<ctx_json>`` members:
#
# * ``build_dir`` - scratch root for the generated mini-project and the ExternalProject tree;
# * ``install_dir`` - install prefix (the store slot);
# * ``source`` - object ``{ type, url?, rev?, sha256?, path? }`` (git | url | local) resolved by
#   ``cdpm_prepare_source``; ExternalProject performs the actual download;
# * ``patches`` - array of absolute patch file paths applied via ``PATCH_COMMAND`` (``git apply``);
# * ``options`` - canonical effective options object (forwarded as Configure flags);
# * ``build`` - object from package metadata containing ``configure_target_map``;
# * ``toolchain`` / ``build_type`` / ``prefix_path`` / ``module_path`` / ``user_file`` -
#   optional, extracted for contract compatibility.
function(cdpm_bs_openssl_build ctx_json)
    block(SCOPE_FOR VARIABLES)
        # Required fields.
        string(JSON build_dir   GET "${ctx_json}" "build_dir")
        string(JSON install_dir GET "${ctx_json}" "install_dir")
        string(JSON source      GET "${ctx_json}" "source")
        string(JSON src_type    GET "${source}" "type")

        # If a previous "cdpm clean" removed the install directory but left ExternalProject stamps behind,
        # wipe the stamps so the install step actually runs this time.
        _cdpm_invalidate_ep_stamps("${build_dir}" "${install_dir}")

        # Optional members default to empty when absent.
        foreach(member toolchain build_type prefix_path module_path user_file)
            string(JSON ${member} ERROR_VARIABLE e_member GET "${ctx_json}" "${member}")
            if(e_member)
                set(${member} "")
            endif()
        endforeach()

        string(JSON patches ERROR_VARIABLE e_patches GET "${ctx_json}" "patches")
        if(e_patches)
            set(patches "[]")
        endif()

        # ---- Perl -----------------------------------------------------------------
        find_program(perl_exe NAMES perl)
        if(NOT perl_exe)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] openssl: Perl is required (5.10+). "
                "Install Perl or set PERL_EXECUTABLE.")
        endif()

        # ---- Configure target -----------------------------------------------------
        _cdpm_openssl_configure_target("${ctx_json}" target)
        if(target STREQUAL "")
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            _cdpm_get_host_processor(host_proc)
            set(platform_key "${CMAKE_HOST_SYSTEM_NAME}-${host_proc}")
            message(FATAL_ERROR "[cdpm] openssl: no configure target for platform "
                "'${platform_key}'. "
                "Add it to configure_target_map in the package registry.")
        endif()

        # ---- Configure args -------------------------------------------------------
        _cdpm_openssl_configure_args("${ctx_json}" configure_args)

        # ---- Build/install commands -----------------------------------------------
        include(ProcessorCount)
        ProcessorCount(nproc)
        if(nproc EQUAL 0)
            set(nproc 4)
        endif()

        if(CMAKE_HOST_WIN32)
            set(build_cmd "nmake")
            set(install_cmd "nmake" "install_sw")
        else()
            set(build_cmd "make" "-j${nproc}")
            set(install_cmd "make" "install_sw")
        endif()

        # ---- Mini-project layout --------------------------------------------------
        set(ep_root "${build_dir}/_cdpm_ep")
        set(ep_bin "${ep_root}/_build")
        file(MAKE_DIRECTORY "${ep_root}")

        # ---- Download method (git / url / local) ----------------------------------
        set(download_lines "")
        if(src_type STREQUAL "git")
            string(JSON url GET "${source}" "url")
            string(JSON rev GET "${source}" "rev")
            string(LENGTH "${rev}" rev_length)
            if(NOT rev_length EQUAL 40 OR NOT rev MATCHES [[^[0-9A-Fa-f]+$]])
                _cdpm_cleanup_driver_user_file("${ctx_json}")
                message(FATAL_ERROR "[cdpm] openssl driver: git rev must be exactly 40 hex characters.")
            endif()
            _cdpm_openssl_quote_external_project_value("${url}" url_q)
            _cdpm_openssl_quote_argument("${rev}" rev_q)
            set(download_lines "    GIT_REPOSITORY ${url_q}\n    GIT_TAG ${rev_q}")
        elseif(src_type STREQUAL "url")
            string(JSON url GET "${source}" "url")
            string(JSON sha GET "${source}" "sha256")
            string(LENGTH "${sha}" sha_length)
            if(NOT sha_length EQUAL 64 OR NOT sha MATCHES [[^[0-9A-Fa-f]+$]])
                _cdpm_cleanup_driver_user_file("${ctx_json}")
                message(FATAL_ERROR "[cdpm] openssl driver: URL sha256 must be exactly 64 hex characters.")
            endif()
            _cdpm_openssl_quote_external_project_value("${url}" url_q)
            set(download_lines "    URL ${url_q}\n    URL_HASH SHA256=${sha}")
        elseif(src_type STREQUAL "local")
            string(JSON path GET "${source}" "path")
            _cdpm_openssl_quote_external_project_value("${path}" path_q)
            set(download_lines "    SOURCE_DIR ${path_q}\n    DOWNLOAD_COMMAND \"\"")
        else()
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] openssl driver: unsupported source type '${src_type}'.")
        endif()

        # ---- Patch step -----------------------------------------------------------
        set(patch_line "")
        string(JSON npatch ERROR_VARIABLE e_np LENGTH "${patches}")
        if(NOT e_np AND npatch GREATER 0)
            find_program(GIT_EXECUTABLE NAMES git)
            if(NOT GIT_EXECUTABLE)
                _cdpm_cleanup_driver_user_file("${ctx_json}")
                message(FATAL_ERROR "[cdpm] 'git' not found; required to apply patches.")
            endif()
            _cdpm_openssl_quote_external_project_value("${GIT_EXECUTABLE}" git_q)
            # ``--no-index`` makes ``git apply`` operate purely on the filesystem relative to its working
            # directory (ExternalProject runs PATCH_COMMAND in <SOURCE_DIR>), exactly like ``patch``. Without
            # it, git walks up to any enclosing repository (the cdpm checkout / the consumer's own repo) and
            # resolves the patch paths against that repo's root instead of the isolated source tree, which
            # fails with "patch does not apply". ``--no-index`` keeps the apply self-contained and portable.
            set(patch_cmd "    PATCH_COMMAND")
            math(EXPR last "${npatch} - 1")
            foreach(i RANGE 0 ${last})
                string(JSON p GET "${patches}" ${i})
                _cdpm_openssl_quote_external_project_value("${p}" p_q)
                if(i EQUAL 0)
                    string(APPEND patch_cmd " ${git_q} apply --whitespace=nowarn --no-index ${p_q}")
                else()
                    string(APPEND patch_cmd "\n        COMMAND ${git_q} apply --whitespace=nowarn --no-index ${p_q}")
                endif()
            endforeach()
            set(patch_line "${patch_cmd}")
        endif()

        # ---- Assemble quoted command fragments ------------------------------------
        _cdpm_openssl_quote_argument("${perl_exe}" perl_q)
        _cdpm_openssl_quote_argument("Configure" configure_q)
        _cdpm_openssl_quote_argument("${target}" target_q)
        _cdpm_openssl_quote_argument("--prefix=${install_dir}" prefix_q)
        _cdpm_openssl_quote_argument("--openssldir=${install_dir}/ssl" openssldir_q)

        set(configure_args_block "")
        foreach(arg IN LISTS configure_args)
            _cdpm_openssl_quote_argument("${arg}" arg_q)
            if(configure_args_block STREQUAL "")
                set(configure_args_block "${arg_q}")
            else()
                string(APPEND configure_args_block " ${arg_q}")
            endif()
        endforeach()

        set(build_cmd_block "")
        foreach(token IN LISTS build_cmd)
            _cdpm_openssl_quote_argument("${token}" token_q)
            if(build_cmd_block STREQUAL "")
                set(build_cmd_block "${token_q}")
            else()
                string(APPEND build_cmd_block " ${token_q}")
            endif()
        endforeach()

        set(install_cmd_block "")
        foreach(token IN LISTS install_cmd)
            _cdpm_openssl_quote_argument("${token}" token_q)
            if(install_cmd_block STREQUAL "")
                set(install_cmd_block "${token_q}")
            else()
                string(APPEND install_cmd_block " ${token_q}")
            endif()
        endforeach()

        # ---- Assemble the mini-project --------------------------------------------
        set(ml "cmake_minimum_required(VERSION 3.25)")
        string(APPEND ml "\nproject(openssl_build NONE)")
        string(APPEND ml "\ninclude(ExternalProject)")
        string(APPEND ml "\nExternalProject_Add(cdpm_pkg")
        string(APPEND ml "\n${download_lines}")
        if(NOT patch_line STREQUAL "")
            string(APPEND ml "\n${patch_line}")
        endif()
        string(APPEND ml "\n    BUILD_IN_SOURCE TRUE")
        string(APPEND ml "\n    CONFIGURE_COMMAND ${perl_q} ${configure_q} ${target_q} ${prefix_q} ${openssldir_q}")
        string(APPEND ml " ${configure_args_block}")
        string(APPEND ml "\n    BUILD_COMMAND ${build_cmd_block}")
        string(APPEND ml "\n    INSTALL_COMMAND ${install_cmd_block}")
        string(APPEND ml "\n)")
        string(APPEND ml "\n")
        file(WRITE "${ep_root}/CMakeLists.txt" "${ml}")

        # ---- Configure the mini-project -------------------------------------------
        message(STATUS "[cdpm] openssl/EP: configuring isolated build for ${src_type} source")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -S "${ep_root}" -B "${ep_bin}"
            RESULT_VARIABLE rc
        )
        if(NOT rc EQUAL 0)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] openssl/EP configure failed (exit ${rc}).")
        endif()

        # ---- Drive the ExternalProject (download -> patch -> configure -> build -> install) ----
        message(STATUS "[cdpm] openssl/EP: building -> ${install_dir}")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" --build "${ep_bin}"
            RESULT_VARIABLE rc
        )
        if(NOT rc EQUAL 0)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] openssl/EP build failed (exit ${rc}) -> ${install_dir}")
        endif()

        # ---- Sentinel ---------------------------------------------------------------
        file(TOUCH "${install_dir}/.cdpm_installed")
    endblock()

    _cdpm_cleanup_driver_user_file("${ctx_json}")
endfunction()
