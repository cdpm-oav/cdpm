# cdpm_bs_autotools.cmake - GNU Autotools build-system driver for cdpm.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON iteration helpers.
include(cdpm_utils)

# Shared driver utilities (download/patch/quote helpers).
include(cdpm_bs_common)

# .. rst:
# ``_cdpm_autotools_is_cross_compiling(<ctx_json> <out_result>)``
#
# Returns TRUE when ``ctx_json.toolchain`` is set and the target system name differs from the host.
function(_cdpm_autotools_is_cross_compiling ctx_json out_result)
    set(${out_result} FALSE)
    string(JSON toolchain ERROR_VARIABLE e_toolchain GET "${ctx_json}" "toolchain")
    if(e_toolchain OR toolchain STREQUAL "")
        return(PROPAGATE ${out_result})
    endif()

    set(system_name "${CMAKE_SYSTEM_NAME}")
    if(system_name STREQUAL "")
        set(system_name "${CMAKE_HOST_SYSTEM_NAME}")
    endif()
    if(NOT system_name STREQUAL CMAKE_HOST_SYSTEM_NAME)
        set(${out_result} TRUE)
    endif()
    return(PROPAGATE ${out_result})
endfunction()

# .. rst:
# ``_cdpm_autotools_host_triplet(<ctx_json> <out_triplet>)``
#
# Returns the autotools ``--host`` triplet. The metadata member ``build.host_triplet`` wins when present;
# otherwise a best-effort triplet is derived from ``CMAKE_SYSTEM_PROCESSOR`` and ``CMAKE_SYSTEM_NAME``.
function(_cdpm_autotools_host_triplet ctx_json out_triplet)
    set(${out_triplet} "")
    string(JSON triplet ERROR_VARIABLE e_triplet GET "${ctx_json}" "build" "host_triplet")
    if(NOT e_triplet AND NOT triplet STREQUAL "")
        set(${out_triplet} "${triplet}")
        return(PROPAGATE ${out_triplet})
    endif()

    set(processor "${CMAKE_SYSTEM_PROCESSOR}")
    set(system_name "${CMAKE_SYSTEM_NAME}")
    if(processor STREQUAL "" OR system_name STREQUAL "")
        return(PROPAGATE ${out_triplet})
    endif()
    string(TOLOWER "${processor}-${system_name}" triplet)
    set(${out_triplet} "${triplet}")
    return(PROPAGATE ${out_triplet})
endfunction()

# .. rst:
# ``_cdpm_autotools_configure_env(<ctx_json> <out_env>)``
#
# Builds the ``cmake -E env ...`` prefix for the configure command. Forwards compiler and archiver tool
# variables (CC/CXX/AR/RANLIB), compile/link flags (CFLAGS/CXXFLAGS/LDFLAGS), and ``SDKROOT`` on Apple
# platforms. Only non-empty variables are emitted.
function(_cdpm_autotools_configure_env ctx_json out_env)
    set(env "${CMAKE_COMMAND}" -E env)

    foreach(tool IN ITEMS CC CXX)
        if(tool STREQUAL "CC")
            set(tool_value "${CMAKE_C_COMPILER}")
        else()
            set(tool_value "${CMAKE_CXX_COMPILER}")
        endif()
        if(NOT tool_value STREQUAL "")
            list(APPEND env "${tool}=${tool_value}")
        endif()
    endforeach()

    # Prefer compiler-provided archiver helpers, fall back to the standalone tools.
    set(ar_value "${CMAKE_C_COMPILER_AR}")
    if(ar_value STREQUAL "")
        set(ar_value "${CMAKE_AR}")
    endif()
    if(NOT ar_value STREQUAL "")
        list(APPEND env "AR=${ar_value}")
    endif()

    set(ranlib_value "${CMAKE_C_COMPILER_RANLIB}")
    if(ranlib_value STREQUAL "")
        set(ranlib_value "${CMAKE_RANLIB}")
    endif()
    if(NOT ranlib_value STREQUAL "")
        list(APPEND env "RANLIB=${ranlib_value}")
    endif()

    foreach(flags IN ITEMS CFLAGS CXXFLAGS LDFLAGS)
        if(flags STREQUAL "CFLAGS")
            set(flags_value "${CMAKE_C_FLAGS}")
        elseif(flags STREQUAL "CXXFLAGS")
            set(flags_value "${CMAKE_CXX_FLAGS}")
        else()
            set(flags_value "${CMAKE_SHARED_LINKER_FLAGS}")
        endif()
        if(NOT flags_value STREQUAL "")
            list(APPEND env "${flags}=${flags_value}")
        endif()
    endforeach()

    if(NOT "${CMAKE_OSX_SYSROOT}" STREQUAL "")
        list(APPEND env "SDKROOT=${CMAKE_OSX_SYSROOT}")
    endif()

    set(${out_env} "${env}")
    return(PROPAGATE ${out_env})
endfunction()

# .. rst:
# ``_cdpm_autotools_configure_args(<ctx_json> <out_args>)``
#
# Translates the effective ``options`` object and the metadata ``build.configure_args`` list into native
# autotools ``configure`` arguments:
#
# * boolean ``true"  -> ``--enable-<key>``
# * boolean ``false" -> ``--disable-<key>``
# * non-empty string  -> ``--with-<key>=<val>``
# * empty string      -> ``--without-<key>``
# * key starting with ``--`` -> passed through unchanged (escape hatch)
function(_cdpm_autotools_configure_args ctx_json out_args)
    set(args "")

    string(JSON options ERROR_VARIABLE e_options GET "${ctx_json}" "options")
    if(NOT e_options)
        set(option_keys "")
        _cdpm_json_foreach("${options}" option_keys)
        foreach(key IN LISTS option_keys)
            _cdpm_json_get("${options}" "${key}" val val_type)
            if(key MATCHES [[^--]])
                list(APPEND args "${key}")
            elseif(val_type STREQUAL "BOOLEAN")
                if(val)
                    list(APPEND args "--enable-${key}")
                else()
                    list(APPEND args "--disable-${key}")
                endif()
            elseif(val_type STREQUAL "STRING")
                if(val STREQUAL "")
                    list(APPEND args "--without-${key}")
                else()
                    list(APPEND args "--with-${key}=${val}")
                endif()
            else()
                list(APPEND args "--with-${key}=${val}")
            endif()
        endforeach()
    endif()

    string(JSON configure_args ERROR_VARIABLE e_ca GET "${ctx_json}" "build" "configure_args")
    if(NOT e_ca)
        string(JSON nca LENGTH "${configure_args}")
        if(nca GREATER 0)
            math(EXPR last "${nca} - 1")
            foreach(i RANGE 0 ${last})
                string(JSON arg GET "${configure_args}" ${i})
                list(APPEND args "${arg}")
            endforeach()
        endif()
    endif()

    set(${out_args} "${args}")
    return(PROPAGATE ${out_args})
endfunction()

# .. rst:
# ``cdpm_bs_autotools_build(<ctx_json>)``
#
# Builds and installs a GNU Autotools package in isolation via ``ExternalProject``. A standalone
# mini-project calls ``ExternalProject_Add`` with a custom ``CONFIGURE_COMMAND``
# (``<SOURCE_DIR>/configure --prefix=<install_dir> ...``), ``BUILD_COMMAND`` (``make -j<nproc>``), and
# ``INSTALL_COMMAND`` (``make install``). The mini-project is driven with
# ``execute_process(cmake -S/-B ...)`` + ``cmake --build``, exactly like the cmake driver.
#
# ``<ctx_json>`` members:
#
# * ``build_dir`` - scratch root for the generated mini-project and the ExternalProject tree;
# * ``install_dir`` - install prefix (the store slot);
# * ``source`` - object ``{ type, url?, rev?, sha256?, path? }`` (git | url | local) resolved by
#   ``cdpm_prepare_source``; ExternalProject performs the actual download;
# * ``patches`` - array of absolute patch file paths applied via ``PATCH_COMMAND`` (``git apply``);
# * ``options`` - canonical effective options object (translated to ``configure`` flags);
# * ``toolchain`` - path to the prepared wrapper toolchain (used to detect cross-compilation);
# * ``build`` - object from package metadata containing ``host_triplet``, ``configure_args``,
#   and ``parallel``;
# * ``build_type`` / ``prefix_path`` / ``module_path`` / ``user_file`` / ``program_path`` /
#   ``execution_path`` - optional, extracted for contract compatibility.
function(cdpm_bs_autotools_build ctx_json)
    if(CMAKE_HOST_WIN32)
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] autotools driver: native autotools builds are unsupported on Windows.")
    endif()

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
        foreach(member toolchain execution_path program_path build_type prefix_path module_path user_file)
            string(JSON ${member} ERROR_VARIABLE e_member GET "${ctx_json}" "${member}")
            if(e_member)
                set(${member} "")
            endif()
        endforeach()

        string(JSON patches ERROR_VARIABLE e_patches GET "${ctx_json}" "patches")
        if(e_patches)
            set(patches "[]")
        endif()

        string(JSON options ERROR_VARIABLE e_options GET "${ctx_json}" "options")
        if(e_options)
            set(options "{}")
        endif()

        # ---- Required tools -------------------------------------------------------
        find_program(make_exe NAMES gmake make)
        if(NOT make_exe)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] autotools driver: make was not found on the POSIX host.")
        endif()

        include(ProcessorCount)
        ProcessorCount(nproc)
        if(nproc EQUAL 0)
            set(nproc 4)
        endif()

        # ---- Cross-compilation detection ------------------------------------------
        _cdpm_autotools_is_cross_compiling("${ctx_json}" is_cross)
        set(host_triplet "")
        if(is_cross)
            _cdpm_autotools_host_triplet("${ctx_json}" host_triplet)
            if(host_triplet STREQUAL "")
                _cdpm_cleanup_driver_user_file("${ctx_json}")
                message(FATAL_ERROR "[cdpm] autotools driver: cannot determine --host triplet for cross "
                    "compilation (set build.host_triplet in package metadata).")
            endif()
        endif()

        # ---- Configure environment and arguments ----------------------------------
        _cdpm_autotools_configure_env("${ctx_json}" configure_env)
        _cdpm_autotools_configure_args("${ctx_json}" configure_args)

        # ---- Build/install commands -----------------------------------------------
        set(parallel TRUE)
        string(JSON parallel_val ERROR_VARIABLE e_parallel GET "${ctx_json}" "build" "parallel")
        if(NOT e_parallel AND NOT parallel_val)
            set(parallel FALSE)
        endif()

        set(build_cmd "${make_exe}")
        if(parallel)
            list(APPEND build_cmd "-j${nproc}")
        endif()
        set(install_cmd "${make_exe}" "install")

        # ---- Mini-project layout --------------------------------------------------
        set(ep_root "${build_dir}/_cdpm_ep")
        set(ep_bin "${ep_root}/_build")
        file(MAKE_DIRECTORY "${ep_root}")

        # ---- Download and patch lines (from common utilities) ---------------------
        _cdpm_bs_download_lines("${source}" download_lines)
        _cdpm_bs_patch_line("${patches}" patch_line)

        # ---- Assemble quoted command fragments ------------------------------------
        set(configure_cmd "")
        list(APPEND configure_cmd ${configure_env})
        list(APPEND configure_cmd "<SOURCE_DIR>/configure")
        list(APPEND configure_cmd "--prefix=${install_dir}")
        if(is_cross)
            list(APPEND configure_cmd "--host=${host_triplet}")
        endif()
        list(APPEND configure_cmd ${configure_args})

        _cdpm_bs_quote_command_block("${configure_cmd}" configure_block)
        _cdpm_bs_quote_command_block("${build_cmd}" build_block)
        _cdpm_bs_quote_command_block("${install_cmd}" install_block)

        # ---- Assemble the mini-project --------------------------------------------
        _cdpm_bs_miniproject_header("autotools_build" ml)
        string(APPEND ml "\nExternalProject_Add(cdpm_pkg")
        string(APPEND ml "\n${download_lines}")
        if(NOT patch_line STREQUAL "")
            string(APPEND ml "\n${patch_line}")
        endif()
        string(APPEND ml "\n    BUILD_IN_SOURCE TRUE")
        string(APPEND ml "\n    CONFIGURE_COMMAND ${configure_block}")
        string(APPEND ml "\n    BUILD_COMMAND ${build_block}")
        string(APPEND ml "\n    INSTALL_COMMAND ${install_block}")
        string(APPEND ml "\n)")
        string(APPEND ml "\n")
        file(WRITE "${ep_root}/CMakeLists.txt" "${ml}")

        # ---- Configure the mini-project -------------------------------------------
        message(STATUS "[cdpm] autotools/EP: configuring isolated build for ${src_type} source")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -S "${ep_root}" -B "${ep_bin}"
            RESULT_VARIABLE rc
        )
        if(NOT rc EQUAL 0)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] autotools/EP configure failed (exit ${rc}).")
        endif()

        # ---- Drive the ExternalProject (download -> patch -> configure -> build -> install) ----
        message(STATUS "[cdpm] autotools/EP: building -> ${install_dir}")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" --build "${ep_bin}"
            RESULT_VARIABLE rc
        )
        if(NOT rc EQUAL 0)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] autotools/EP build failed (exit ${rc}) -> ${install_dir}")
        endif()

        # ---- Sentinel ---------------------------------------------------------------
        file(TOUCH "${install_dir}/.cdpm_installed")
    endblock()

    _cdpm_cleanup_driver_user_file("${ctx_json}")
endfunction()
