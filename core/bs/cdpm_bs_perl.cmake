# cdpm_bs_perl.cmake - Managed POSIX Perl build driver.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# Shared driver utilities (download/patch/quote helpers).
include(cdpm_bs_common)

# Builds Perl from its own POSIX ``Configure`` script; no pre-existing Perl interpreter is used.
function(cdpm_bs_perl_build ctx_json)
    if(CMAKE_HOST_WIN32)
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] perl driver: managed Perl is supported only on POSIX Darwin/Linux hosts; "
            "Windows is unsupported.")
    endif()
    if(NOT CMAKE_HOST_SYSTEM_NAME MATCHES [[^(Darwin|Linux)$]])
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] perl driver: unsupported host '${CMAKE_HOST_SYSTEM_NAME}' (Darwin/Linux only).")
    endif()

    string(JSON build_dir GET "${ctx_json}" build_dir)
    string(JSON install_dir GET "${ctx_json}" install_dir)
    string(JSON source GET "${ctx_json}" source)
    string(JSON source_type GET "${source}" type)
    string(JSON ep_target GET "${ctx_json}" ep_target)
    string(JSON archive_cache_dir ERROR_VARIABLE e_archive_cache_dir GET "${ctx_json}" archive_cache_dir)
    if(e_archive_cache_dir)
        set(archive_cache_dir "")
    endif()
    _cdpm_invalidate_ep_stamps("${build_dir}" "${install_dir}" "${ep_target}")

    _cdpm_bs_download_lines("${source}" download "${archive_cache_dir}")

    find_program(make_exe NAMES gmake make)
    if(NOT make_exe)
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] perl driver: make was not found on the POSIX host.")
    endif()
    include(ProcessorCount)
    ProcessorCount(nproc)
    if(NOT nproc GREATER 0)
        set(nproc 4)
    endif()
    # The Configure prefix is passed inside single quotes so the shell strips
    # the quotes and Perl sees a bare path. Double-quoted values survive into
    # config.h and break the build when the prefix contains '/'
    # (see SITEARCH_EXP / SITELIB_EXP).
    string(REPLACE "'" "\\'" install_dir_escaped "${install_dir}")
    _cdpm_bs_quote_argument("${make_exe}" make_q)

    set(ep_root "${build_dir}/_cdpm_ep")
    set(ep_bin "${ep_root}/_build")
    file(MAKE_DIRECTORY "${ep_root}")
    _cdpm_bs_miniproject_header("perl_build" project)
    string(APPEND project "ExternalProject_Add(${ep_target}\n${download}\n    BUILD_IN_SOURCE TRUE\n")
    string(APPEND project "    CONFIGURE_COMMAND <SOURCE_DIR>/Configure -des -Dprefix='${install_dir_escaped}'\n")
    string(APPEND project "    BUILD_COMMAND ${make_q} -j${nproc}\n")
    string(APPEND project "    INSTALL_COMMAND ${make_q} install\n)\n")
    file(WRITE "${ep_root}/CMakeLists.txt" "${project}")

    execute_process(COMMAND "${CMAKE_COMMAND}" -S "${ep_root}" -B "${ep_bin}" RESULT_VARIABLE rc)
    if(NOT rc EQUAL 0)
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] perl/EP configure failed (exit ${rc}).")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" --build "${ep_bin}" RESULT_VARIABLE rc)
    if(NOT rc EQUAL 0 OR NOT EXISTS "${install_dir}/bin/perl")
        _cdpm_cleanup_driver_user_file("${ctx_json}")
        message(FATAL_ERROR "[cdpm] perl/EP build failed or did not install '${install_dir}/bin/perl'.")
    endif()
endfunction()
