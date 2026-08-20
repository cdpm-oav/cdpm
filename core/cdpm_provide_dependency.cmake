# cdpm_provide_dependency.cmake - Dependency-provider entry point.

include_guard(GLOBAL)

include(cdpm_resolve)
include(cdpm_verange)

macro(_cdpm_ensure_repos_loaded)
    get_property(_cdpm_repos_loaded GLOBAL PROPERTY CDPM_PROVIDER_REPOS_LOADED)
    if(NOT _cdpm_repos_loaded)
        cdpm_config_load()
        cdpm_load_repos()
        cdpm_read_lockfile()
        set_property(GLOBAL PROPERTY CDPM_PROVIDER_REPOS_LOADED TRUE)
    endif()
    unset(_cdpm_repos_loaded)
endmacro()

# The provider is a macro so the replayed find_package result variables remain in the caller's scope.
macro(cdpm_provide_dependency method_type)
    get_property(_cdpm_replay_active GLOBAL PROPERTY CDPM_PROVIDER_REPLAY_ACTIVE)

    if(_cdpm_replay_active AND "${method_type}" STREQUAL "FIND_PACKAGE")
        # Not a managed package in this graph — let CMake's default find logic handle it.
        # If REQUIRED and not found, find_package will fatal on its own.
        find_package(${ARGN} BYPASS_PROVIDER)
        unset(_cdpm_replay_active)
    elseif(CDPM_DISABLE OR CDPM_BYPASS OR NOT "${method_type}" STREQUAL "FIND_PACKAGE")
        find_package(${ARGN} BYPASS_PROVIDER)
        unset(_cdpm_replay_active)
    else()
        block(PROPAGATE
            CMAKE_PREFIX_PATH
            _cdpm_pkg_name _cdpm_install_dir _cdpm_fp_REQUIRED _cdpm_known _cdpm_do_find
        )
            _cdpm_ensure_repos_loaded()
            set(_cdpm_pkg_name "${ARGV1}")
            set(_cdpm_install_dir "")
            set(_cdpm_do_find TRUE)
            cmake_parse_arguments(_cdpm_fp "REQUIRED;QUIET" "" "" ${ARGN})
            set(_cdpm_req_ver "")
            if(DEFINED _cdpm_fp_UNPARSED_ARGUMENTS)
                list(LENGTH _cdpm_fp_UNPARSED_ARGUMENTS _cdpm_fp_nargs)
                if(_cdpm_fp_nargs GREATER 1)
                    list(GET _cdpm_fp_UNPARSED_ARGUMENTS 1 _cdpm_maybe_ver)
                    _cdpm_require_exact_version("${_cdpm_pkg_name}" "find_package" "${_cdpm_maybe_ver}" _cdpm_req_ver)
                endif()
            endif()

            cdpm_find_package_in_repo("${_cdpm_pkg_name}" _cdpm_known _cdpm_pkg_key _cdpm_meta)
            if(NOT _cdpm_known)
                # Child builds of managed packages reuse the provider; they are always considered
                # nested and must be allowed to fall back to the system find_package.
                if(NOT CDPM_ALLOW_SYSTEM_PACKAGES AND NOT DEFINED CDPM_INJECT_ROOT)
                    message(FATAL_ERROR "[cdpm] Package '${_cdpm_pkg_name}' is not provided by any loaded registry.\n"
                        "Set CDPM_ALLOW_SYSTEM_PACKAGES=ON to fall back to the system find_package, "
                        "or add a registry that provides it.")
                endif()
                # Package not in any loaded repository; let the default find_package below handle it.
            else()
                cdpm_resolve_and_build("${_cdpm_pkg_key}" "${_cdpm_req_ver}" _cdpm_context)
                string(JSON _cdpm_install_dir GET "${_cdpm_context}" install_dir)
                string(JSON _cdpm_prefix_count LENGTH "${_cdpm_context}" prefixes)
                if(_cdpm_prefix_count GREATER 0)
                    math(EXPR _cdpm_prefix_last "${_cdpm_prefix_count} - 1")
                    foreach(_cdpm_i RANGE 0 ${_cdpm_prefix_last})
                        string(JSON _cdpm_prefix GET "${_cdpm_context}" prefixes ${_cdpm_i})
                        list(APPEND _cdpm_prefixes "${_cdpm_prefix}")
                    endforeach()
                    list(PREPEND CMAKE_PREFIX_PATH ${_cdpm_prefixes})
                endif()
            endif()
        endblock()

        if(_cdpm_known)
            get_property(_cdpm_saved_guard GLOBAL PROPERTY CDPM_PROVIDER_REPLAY_ACTIVE)
            set_property(GLOBAL PROPERTY CDPM_PROVIDER_REPLAY_ACTIVE TRUE)
        endif()

        if(_cdpm_do_find)
            find_package(${ARGN} BYPASS_PROVIDER)
        endif()

        if(_cdpm_known)
            set_property(GLOBAL PROPERTY CDPM_PROVIDER_REPLAY_ACTIVE "${_cdpm_saved_guard}")
        endif()

        if(_cdpm_fp_REQUIRED AND NOT "${_cdpm_install_dir}" STREQUAL "" AND NOT ${_cdpm_pkg_name}_FOUND)
            message(FATAL_ERROR "[cdpm] Package '${_cdpm_pkg_name}' was built and installed to "
                "'${_cdpm_install_dir}', but find_package still could not locate it.")
        endif()

        foreach(_cdpm_var IN ITEMS pkg_name install_dir fp_REQUIRED known do_find saved_guard)
            unset(_cdpm_${_cdpm_var})
        endforeach()

        unset(_cdpm_var)
        unset(_cdpm_replay_active)
        unset(_cdpm_saved_guard)
    endif()
endmacro()
