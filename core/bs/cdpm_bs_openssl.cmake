# cdpm_bs_openssl.cmake - OpenSSL build-system driver for cdpm (perl Configure + make/nmake via ExternalProject).

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON iteration helpers.
include(cdpm_utils)

# Shared driver utilities (download/patch/quote helpers).
include(cdpm_bs_common)

# .. rst:
# ``_cdpm_openssl_configure_target(<ctx_json> <out_target>)``
#
# Selects the OpenSSL Configure target for the target platform from
# ``ctx_json.build.configure_target_map``.
function(_cdpm_openssl_configure_target ctx_json out_target)
    string(JSON target_map ERROR_VARIABLE err GET "${ctx_json}" "build" "configure_target_map")
    if(err)
        set(${out_target} "")
        return(PROPAGATE ${out_target})
    endif()

    set(system_name "${CMAKE_SYSTEM_NAME}")
    set(processor "${CMAKE_SYSTEM_PROCESSOR}")
    if(system_name STREQUAL "")
        set(system_name "${CMAKE_HOST_SYSTEM_NAME}")
    endif()
    if(processor STREQUAL "")
        _cdpm_get_host_processor(processor)
    endif()
    if(system_name STREQUAL "iOS" AND CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
        set(platform_key "iOSSimulator-${processor}")
    else()
        set(platform_key "${system_name}-${processor}")
    endif()
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
        foreach(member toolchain build_type prefix_path module_path user_file program_path execution_path archive_cache_dir)
            string(JSON ${member} ERROR_VARIABLE e_member GET "${ctx_json}" "${member}")
            if(e_member)
                set(${member} "")
            endif()
        endforeach()

        string(JSON patches ERROR_VARIABLE e_patches GET "${ctx_json}" "patches")
        if(e_patches)
            set(patches "[]")
        endif()

        # ---- Managed Perl ---------------------------------------------------------
        find_program(perl_exe NAMES perl PATHS ${program_path} NO_DEFAULT_PATH)
        if(NOT perl_exe)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] openssl: managed host dependency Perl was not found in host_prefixes; "
                "system Perl fallback is intentionally disabled.")
        endif()

        # ---- Configure target -----------------------------------------------------
        _cdpm_openssl_configure_target("${ctx_json}" target)
        if(target STREQUAL "")
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] openssl: no configure target for platform "
                "'${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}'. "
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
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] openssl: managed Perl/OpenSSL builds are unsupported on Windows.")
        endif()
        set(build_cmd "make" "-j${nproc}")
        set(install_cmd "make" "install_sw")

        # ---- Mini-project layout --------------------------------------------------
        set(ep_root "${build_dir}/_cdpm_ep")
        set(ep_bin "${ep_root}/_build")
        file(MAKE_DIRECTORY "${ep_root}")

        # ---- Download method (git / url / local) ----------------------------------
        _cdpm_bs_download_lines("${source}" download_lines "${archive_cache_dir}")

        # ---- Patch step -----------------------------------------------------------
        _cdpm_bs_patch_line("${patches}" patch_line)

        # ---- Assemble quoted command fragments ------------------------------------
        _cdpm_bs_quote_argument("${perl_exe}" perl_q)
        _cdpm_bs_quote_argument("Configure" configure_q)
        _cdpm_bs_quote_argument("${target}" target_q)
        _cdpm_bs_quote_argument("--prefix=${install_dir}" prefix_q)
        _cdpm_bs_quote_argument("--openssldir=${install_dir}/ssl" openssldir_q)

        _cdpm_bs_quote_command_block("${configure_args}" configure_args_block)
        _cdpm_bs_quote_command_block("${build_cmd}" build_cmd_block)
        _cdpm_bs_quote_command_block("${install_cmd}" install_cmd_block)

        # ---- Assemble the mini-project --------------------------------------------
        _cdpm_bs_miniproject_header("openssl_build" ml)
        string(APPEND ml "ExternalProject_Add(cdpm_pkg")
        string(APPEND ml "\n${download_lines}")
        if(NOT patch_line STREQUAL "")
            string(APPEND ml "\n${patch_line}")
        endif()
        string(APPEND ml "\n    BUILD_IN_SOURCE TRUE")
        set(configure_env "${CMAKE_COMMAND}" -E env)
        foreach(tool IN ITEMS CC CXX AR RANLIB)
            if(tool STREQUAL "CC")
                set(tool_value "${CMAKE_C_COMPILER}")
            elseif(tool STREQUAL "CXX")
                set(tool_value "${CMAKE_CXX_COMPILER}")
            elseif(tool STREQUAL "AR")
                set(tool_value "${CMAKE_C_COMPILER_AR}")
            else()
                set(tool_value "${CMAKE_C_COMPILER_RANLIB}")
            endif()
            if(NOT tool_value STREQUAL "")
                list(APPEND configure_env "${tool}=${tool_value}")
            endif()
        endforeach()
        if(NOT CMAKE_OSX_SYSROOT STREQUAL "")
            list(APPEND configure_env "SDKROOT=${CMAKE_OSX_SYSROOT}")
        endif()
        _cdpm_bs_quote_command_block("${configure_env}" configure_env_block)
        string(APPEND ml "\n    CONFIGURE_COMMAND ${configure_env_block} ${perl_q} ${configure_q} ${target_q} ${prefix_q} ${openssldir_q}")
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
