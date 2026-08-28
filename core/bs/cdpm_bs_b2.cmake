# cdpm_bs_b2.cmake - Boost.Build (b2) build-system driver for cdpm.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON iteration helpers.
include(cdpm_utils)

# Shared driver utilities (download/patch/quote helpers).
include(cdpm_bs_common)

# .. rst:
# ``_cdpm_b2_toolset(<ctx_json> <out_toolset>)``
#
# Maps ``CMAKE_CXX_COMPILER_ID`` to a b2 toolset name. Falls back to ``build.toolset`` from package
# metadata when the compiler id is unknown.
function(_cdpm_b2_toolset ctx_json out_toolset)
    set(toolset "")
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        set(toolset "gcc")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        set(toolset "clang")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
        set(toolset "clang")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        set(toolset "msvc")
    elseif(CMAKE_CXX_COMPILER_ID MATCHES [[^(Intel|IntelLLVM)$]])
        set(toolset "intel")
    endif()

    if(toolset STREQUAL "")
        string(JSON meta_toolset ERROR_VARIABLE err GET "${ctx_json}" "build" "toolset")
        if(NOT err AND NOT meta_toolset STREQUAL "")
            set(toolset "${meta_toolset}")
        endif()
    endif()

    set(${out_toolset} "${toolset}")
    return(PROPAGATE ${out_toolset})
endfunction()

# .. rst:
# ``_cdpm_b2_variant(<ctx_json> <out_variant>)``
#
# Maps ``CMAKE_BUILD_TYPE`` to a b2 ``variant=`` value. Empty build type means the variant is omitted
# so b2 uses its own default.
function(_cdpm_b2_variant ctx_json out_variant)
    set(variant "")
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        set(variant "debug")
    elseif(CMAKE_BUILD_TYPE MATCHES [[^(Release|RelWithDebInfo|MinSizeRel)$]])
        set(variant "release")
    endif()

    set(${out_variant} "${variant}")
    return(PROPAGATE ${out_variant})
endfunction()

# .. rst:
# ``_cdpm_b2_address_model(<ctx_json> <out_am>)``
#
# Returns b2 ``address-model=`` (``32`` or ``64``) from ``CMAKE_SIZEOF_VOID_P``.
function(_cdpm_b2_address_model ctx_json out_am)
    set(am "64")
    if(DEFINED CMAKE_SIZEOF_VOID_P AND NOT CMAKE_SIZEOF_VOID_P STREQUAL "")
        math(EXPR am "${CMAKE_SIZEOF_VOID_P} * 8")
    endif()

    set(${out_am} "${am}")
    return(PROPAGATE ${out_am})
endfunction()

# .. rst:
# ``_cdpm_b2_link_mode(<ctx_json> <out_link>)``
#
# Returns b2 ``link=`` mode from ``options.BOOST_LINK``; defaults to ``shared``.
function(_cdpm_b2_link_mode ctx_json out_link)
    set(link "shared")
    string(JSON options ERROR_VARIABLE err GET "${ctx_json}" "options")
    if(NOT err)
        _cdpm_json_get("${options}" "BOOST_LINK" link_val link_type)
        if(NOT link_type STREQUAL "" AND NOT link_val STREQUAL "")
            set(link "${link_val}")
        endif()
    endif()

    set(${out_link} "${link}")
    return(PROPAGATE ${out_link})
endfunction()

# .. rst:
# ``_cdpm_b2_libraries(<ctx_json> <out_args>)``
#
# Translates ``options.BOOST_BUILD_LIBRARIES`` (semicolon-separated list) into ``--with-<lib>`` b2
# arguments. An empty list means building all libraries (b2 default).
function(_cdpm_b2_libraries ctx_json out_args)
    set(args "")
    string(JSON options ERROR_VARIABLE err GET "${ctx_json}" "options")
    if(NOT err)
        _cdpm_json_get("${options}" "BOOST_BUILD_LIBRARIES" libs libs_type)
        if(NOT libs_type STREQUAL "" AND NOT libs STREQUAL "")
            foreach(lib IN LISTS libs)
                list(APPEND args "--with-${lib}")
            endforeach()
        endif()
    endif()

    set(${out_args} "${args}")
    return(PROPAGATE ${out_args})
endfunction()

# .. rst:
# ``_cdpm_b2_user_config_jam(<ctx_json> <out_jam_path> <out_needed>)``
#
# Generates ``<build_dir>/user-config.jam`` when a toolchain file is present, telling b2 which compiler
# to use. Returns the path and a boolean indicating whether the file was written.
function(_cdpm_b2_user_config_jam ctx_json out_jam_path out_needed)
    set(jam_path "")
    set(needed FALSE)

    string(JSON build_dir GET "${ctx_json}" "build_dir")
    string(JSON toolchain ERROR_VARIABLE err GET "${ctx_json}" "toolchain")
    if(NOT err AND NOT toolchain STREQUAL "")
        _cdpm_b2_toolset("${ctx_json}" toolset)
        if(toolset STREQUAL "")
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] b2 driver: cannot determine toolset for user-config.jam.")
        endif()

        set(jam_path "${build_dir}/user-config.jam")
        set(content "using ${toolset} : : ${CMAKE_CXX_COMPILER} ;\n")
        file(WRITE "${jam_path}" "${content}")
        set(needed TRUE)
    endif()

    set(${out_jam_path} "${jam_path}")
    set(${out_needed} "${needed}")
    return(PROPAGATE ${out_jam_path} ${out_needed})
endfunction()

# .. rst:
# ``_cdpm_b2_bootstrap_args(<ctx_json> <toolset> <out_args>)``
#
# Builds the arguments passed to ``bootstrap.sh``. Always includes ``--with-toolset=<toolset>`` and
# appends any ``build.bootstrap_args`` from package metadata.
function(_cdpm_b2_bootstrap_args ctx_json toolset out_args)
    set(args "--with-toolset=${toolset}")

    string(JSON bootstrap_args ERROR_VARIABLE err GET "${ctx_json}" "build" "bootstrap_args")
    if(NOT err)
        string(JSON n LENGTH "${bootstrap_args}")
        if(n GREATER 0)
            math(EXPR last "${n} - 1")
            foreach(i RANGE 0 ${last})
                string(JSON arg GET "${bootstrap_args}" ${i})
                list(APPEND args "${arg}")
            endforeach()
        endif()
    endif()

    set(${out_args} "${args}")
    return(PROPAGATE ${out_args})
endfunction()

# .. rst:
# ``_cdpm_b2_build_args(<ctx_json> <toolset> <variant> <am> <link> <libs> <out_args>)``
#
# Assembles the full b2 command-line argument list. Adds toolset, variant, address model, link mode,
# layout, prefix, Python/ICU defaults, selected libraries, user-config, custom flags, and parallel build.
function(_cdpm_b2_build_args ctx_json toolset variant am link libs out_args)
    set(args "")
    list(APPEND args "toolset=${toolset}")
    if(NOT variant STREQUAL "")
        list(APPEND args "variant=${variant}")
    endif()
    list(APPEND args "link=${link}")
    list(APPEND args "address-model=${am}")
    list(APPEND args "--layout=versioned")

    string(JSON install_dir GET "${ctx_json}" "install_dir")
    list(APPEND args "--prefix=${install_dir}")
    list(APPEND args "--without-python")

    string(JSON options ERROR_VARIABLE err GET "${ctx_json}" "options")
    set(with_icu FALSE)
    if(NOT err)
        _cdpm_json_get("${options}" "BOOST_WITH_ICU" with_icu_val with_icu_type)
        if(with_icu_type STREQUAL "BOOLEAN" AND with_icu_val)
            set(with_icu TRUE)
        endif()
    endif()
    if(NOT with_icu)
        list(APPEND args "--disable-icu")
    endif()

    include(ProcessorCount)
    ProcessorCount(nproc)
    if(nproc EQUAL 0)
        set(nproc 4)
    endif()

    set(parallel TRUE)
    string(JSON parallel_val ERROR_VARIABLE e_parallel GET "${ctx_json}" "build" "parallel")
    if(NOT e_parallel AND NOT parallel_val)
        set(parallel FALSE)
    endif()
    if(parallel)
        list(APPEND args "-j${nproc}")
    endif()

    list(APPEND args ${libs})

    _cdpm_b2_user_config_jam("${ctx_json}" user_config needed)
    if(needed)
        list(APPEND args "--user-config=${user_config}")
    endif()

    if(NOT err)
        _cdpm_json_get("${options}" "BOOST_CXXFLAGS" cxxflags cxxflags_type)
        if(NOT cxxflags_type STREQUAL "" AND NOT cxxflags STREQUAL "")
            list(APPEND args "cxxflags=${cxxflags}")
        endif()

        _cdpm_json_get("${options}" "BOOST_LINKFLAGS" linkflags linkflags_type)
        if(NOT linkflags_type STREQUAL "" AND NOT linkflags STREQUAL "")
            list(APPEND args "linkflags=${linkflags}")
        endif()
    endif()

    set(${out_args} "${args}")
    return(PROPAGATE ${out_args})
endfunction()

# .. rst:
# ``cdpm_bs_b2_build(<ctx_json>)``
#
# Builds and installs a Boost package via Boost.Build (b2) in isolation through ``ExternalProject``.
# A standalone mini-project calls ``ExternalProject_Add`` with custom ``CONFIGURE_COMMAND``
# (``bootstrap.sh``), ``BUILD_COMMAND`` (``b2``), and ``INSTALL_COMMAND`` (``b2 install``). The
# mini-project is driven with ``execute_process(cmake -S/-B ...)`` + ``cmake --build``, exactly like
# the other non-CMake drivers.
#
# ``<ctx_json>`` members:
#
# * ``build_dir`` - scratch root for the generated mini-project and the ExternalProject tree;
# * ``install_dir`` - install prefix (the store slot);
# * ``source`` - object ``{ type, url?, rev?, sha256?, path? }`` (git | url | local) resolved by
#   ``cdpm_prepare_source``; ExternalProject performs the actual download;
# * ``patches`` - array of absolute patch file paths applied via ``PATCH_COMMAND`` (``git apply``);
# * ``options`` - canonical effective options object (``BOOST_LINK``, ``BOOST_BUILD_LIBRARIES``,
#   ``BOOST_WITH_ICU``, ``BOOST_CXXFLAGS``, ``BOOST_LINKFLAGS``);
# * ``toolchain`` - path to the prepared wrapper toolchain (used to generate ``user-config.jam``);
# * ``build`` - object from package metadata containing ``toolset``, ``bootstrap_args``, and ``parallel``;
# * ``build_type`` / ``prefix_path`` / ``module_path`` / ``user_file`` / ``program_path`` /
#   ``execution_path`` / ``archive_cache_dir`` - optional, extracted for contract compatibility.
function(cdpm_bs_b2_build ctx_json)
    if(CMAKE_HOST_WIN32)
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] b2 driver: Boost.Build on Windows is unsupported in this version.")
    endif()

    block(SCOPE_FOR VARIABLES)
        # Required fields.
        string(JSON build_dir   GET "${ctx_json}" "build_dir")
        string(JSON install_dir GET "${ctx_json}" "install_dir")
        string(JSON source      GET "${ctx_json}" "source")
        string(JSON src_type    GET "${source}" "type")
        string(JSON ep_target   GET "${ctx_json}" "ep_target")

        # If a previous "cdpm clean" removed the install directory but left ExternalProject stamps behind,
        # wipe the stamps so the install step actually runs this time.
        _cdpm_invalidate_ep_stamps("${build_dir}" "${install_dir}" "${ep_target}")

        # Optional members default to empty when absent.
        foreach(member toolchain build_type prefix_path module_path user_file program_path
                execution_path archive_cache_dir)
            string(JSON ${member} ERROR_VARIABLE e_member GET "${ctx_json}" "${member}")
            if(e_member)
                set(${member} "")
            endif()
        endforeach()

        string(JSON patches ERROR_VARIABLE e_patches GET "${ctx_json}" "patches")
        if(e_patches)
            set(patches "[]")
        endif()

        # ---- Toolchain selection --------------------------------------------------
        _cdpm_b2_toolset("${ctx_json}" toolset)
        if(toolset STREQUAL "")
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] b2 driver: cannot determine toolset from CMAKE_CXX_COMPILER_ID "
                "'${CMAKE_CXX_COMPILER_ID}' and no build.toolset metadata provided.")
        endif()

        # ---- b2 build attributes --------------------------------------------------
        _cdpm_b2_variant("${ctx_json}" variant)
        _cdpm_b2_address_model("${ctx_json}" am)
        _cdpm_b2_link_mode("${ctx_json}" link)
        _cdpm_b2_libraries("${ctx_json}" libs)

        # ---- Bootstrap and b2 arguments -------------------------------------------
        _cdpm_b2_bootstrap_args("${ctx_json}" "${toolset}" bootstrap_args)
        _cdpm_b2_build_args("${ctx_json}" "${toolset}" "${variant}" "${am}" "${link}" "${libs}" build_args)

        # ---- Environment prefix (cmake -E env ...) --------------------------------
        set(env_prefix "${CMAKE_COMMAND}" -E env)
        foreach(tool IN ITEMS CC CXX)
            if(tool STREQUAL "CC")
                set(tool_value "${CMAKE_C_COMPILER}")
            else()
                set(tool_value "${CMAKE_CXX_COMPILER}")
            endif()
            if(NOT tool_value STREQUAL "")
                list(APPEND env_prefix "${tool}=${tool_value}")
            endif()
        endforeach()
        if(NOT execution_path STREQUAL "")
            list(APPEND env_prefix "PATH=${execution_path}")
        endif()

        # ---- Mini-project layout --------------------------------------------------
        set(ep_root "${build_dir}/_cdpm_ep")
        set(ep_bin "${ep_root}/_build")
        file(MAKE_DIRECTORY "${ep_root}")

        # ---- Download and patch lines (from common utilities) ---------------------
        _cdpm_bs_download_lines("${source}" download_lines "${archive_cache_dir}")
        _cdpm_bs_patch_line("${patches}" patch_line)

        # ---- Assemble quoted command fragments ------------------------------------
        set(configure_cmd "")
        list(APPEND configure_cmd ${env_prefix})
        list(APPEND configure_cmd "<SOURCE_DIR>/bootstrap.sh")
        list(APPEND configure_cmd ${bootstrap_args})
        _cdpm_bs_quote_command_block("${configure_cmd}" configure_block)

        set(build_cmd "")
        list(APPEND build_cmd ${env_prefix})
        list(APPEND build_cmd "<SOURCE_DIR>/b2")
        list(APPEND build_cmd ${build_args})
        _cdpm_bs_quote_command_block("${build_cmd}" build_block)

        set(install_cmd "")
        list(APPEND install_cmd ${env_prefix})
        list(APPEND install_cmd "<SOURCE_DIR>/b2")
        list(APPEND install_cmd "install")
        list(APPEND install_cmd ${build_args})
        list(APPEND install_cmd "--prefix=${install_dir}")
        _cdpm_bs_quote_command_block("${install_cmd}" install_block)

        # ---- Assemble the mini-project --------------------------------------------
        _cdpm_bs_miniproject_header("b2_build" ml)
        string(APPEND ml "ExternalProject_Add(${ep_target}")
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
        message(STATUS "[cdpm] b2/EP: configuring isolated build for ${src_type} source")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -S "${ep_root}" -B "${ep_bin}"
            RESULT_VARIABLE rc
        )
        if(NOT rc EQUAL 0)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] b2/EP configure failed (exit ${rc}).")
        endif()

        # ---- Drive the ExternalProject (download -> patch -> bootstrap -> build -> install) ----
        message(STATUS "[cdpm] b2/EP: building -> ${install_dir}")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" --build "${ep_bin}"
            RESULT_VARIABLE rc
        )
        if(NOT rc EQUAL 0)
            _cdpm_cleanup_driver_user_file("${ctx_json}")
            message(FATAL_ERROR "[cdpm] b2/EP build failed (exit ${rc}) -> ${install_dir}")
        endif()
    endblock()

    _cdpm_cleanup_driver_user_file("${ctx_json}")
endfunction()
