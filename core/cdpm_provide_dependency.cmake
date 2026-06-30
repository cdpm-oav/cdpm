# cdpm_provide_dependency.cmake
# The dependency-provider entry point registered via cmake_language(SET_DEPENDENCY_PROVIDER ...).
# Orchestrates: registry load -> version resolve -> config hash -> isolated build/install ->
# CMAKE_PREFIX_PATH injection -> find_package(... BYPASS_PROVIDER).

include_guard(GLOBAL)

# Core modules. cdpm_build pulls in cdpm_config / cdpm_hash / cdpm_toolchain transitively, so the
# provider has cdpm_config_load / cdpm_load_repos / cdpm_find_in_repo / cdpm_resolve_version /
# cdpm_compute_config_hash / cdpm_build_dependency / _cdpm_resolve_store_dir available.
include(cdpm_config)
include(cdpm_build)
include(cdpm_lockfile)

# .. rst:
# ``_cdpm_ensure_repos_loaded()``
#
# Loads the effective configuration and materializes every declared repository exactly once for the
# lifetime of the CMake run, guarded by the ``CDPM_PROVIDER_REPOS_LOADED`` global property. Populates
# ``CDPM_MERGED_REPO`` (consumed by :cmake:command:`cdpm_find_in_repo`).
macro(_cdpm_ensure_repos_loaded)
    get_property(_cdpm_repos_loaded GLOBAL PROPERTY CDPM_PROVIDER_REPOS_LOADED)
    if(NOT _cdpm_repos_loaded)
        cdpm_config_load()
        cdpm_load_repos()
        # Load the lockfile once so the fast-path can consult pinned config hashes.
        cdpm_read_lockfile()
        set_property(GLOBAL PROPERTY CDPM_PROVIDER_REPOS_LOADED TRUE)
    endif()
    unset(_cdpm_repos_loaded)
endmacro()

# .. rst:
# ``cdpm_provide_dependency(<method_type> <args>...)``
#
# Dependency provider for ``FIND_PACKAGE``. Must be a macro (not a function) so that mutations of
# ``CMAKE_PREFIX_PATH`` are visible to the enclosing :cmake:command:`find_package` call that triggered the
# provider.
#
# Flow:
#
# * ``CDPM_DISABLE`` / ``CDPM_BYPASS``, or a non-``FIND_PACKAGE`` method, forward straight to
#   ``find_package(... BYPASS_PROVIDER)``;
# * otherwise the registry is consulted: a known package is resolved (version + config hash), built into
#   the store on demand, its install prefix is prepended to ``CMAKE_PREFIX_PATH``, and the original
#   ``find_package`` is replayed with ``BYPASS_PROVIDER``;
# * an unknown package falls back to the system only when ``CDPM_ALLOW_SYSTEM_PACKAGES`` is ON, else fatal.
#
# The package name passed to ``find_package`` is used directly as the registry key (v1: no
# ``find_package_name`` reverse mapping). Local macro variables are ``_cdpm_``-prefixed to avoid leaking
# into the caller's scope.
macro(cdpm_provide_dependency method_type)
    if(CDPM_DISABLE OR CDPM_BYPASS OR NOT "${method_type}" STREQUAL "FIND_PACKAGE")
        find_package(${ARGN} BYPASS_PROVIDER)
    else()
        # Resolution + isolated build run in a scoped block so all working variables stay local
        # (no manual unset chain). Only the values the trailing find_package() needs leave the
        # block: the prepended CMAKE_PREFIX_PATH plus a tiny bit of diagnostic state. The final
        # find_package(... BYPASS_PROVIDER) is deliberately kept OUTSIDE the block so its result
        # variables (<pkg>_FOUND, <pkg>_DIR, ...) land in the caller's scope -- a macro provides no
        # scope of its own, and block(PROPAGATE) would not forward those plural outputs.
        block(PROPAGATE CMAKE_PREFIX_PATH _cdpm_pkg_name _cdpm_install_dir _cdpm_fp_REQUIRED
            _cdpm_do_find)
            _cdpm_ensure_repos_loaded()

            # ARGV1 is the package name; the rest carries find_package() arguments (version
            # constraint, REQUIRED, QUIET, COMPONENTS, ...) and is forwarded verbatim by the caller.
            set(_cdpm_pkg_name "${ARGV1}")
            set(_cdpm_do_find TRUE)
            set(_cdpm_install_dir "")

            cmake_parse_arguments(_cdpm_fp "REQUIRED;QUIET" "" "" ${ARGN})
            set(_cdpm_req_ver "")
            if(DEFINED _cdpm_fp_UNPARSED_ARGUMENTS)
                list(LENGTH _cdpm_fp_UNPARSED_ARGUMENTS _cdpm_fp_nargs)
                if(_cdpm_fp_nargs GREATER 1)
                    # UNPARSED_ARGUMENTS[0] is the package name; [1] (if version-like) is the
                    # requested version -- find_package() places it immediately after the name.
                    list(GET _cdpm_fp_UNPARSED_ARGUMENTS 1 _cdpm_maybe_ver)
                    if(_cdpm_maybe_ver MATCHES "^[0-9]")
                        set(_cdpm_req_ver "${_cdpm_maybe_ver}")
                    endif()
                endif()
            endif()

            cdpm_find_in_repo("${_cdpm_pkg_name}" _cdpm_found _cdpm_meta)

            if(NOT _cdpm_found)
                if(CDPM_ALLOW_SYSTEM_PACKAGES)
                    message(STATUS "[cdpm] '${_cdpm_pkg_name}' not in registry -- "
                        "falling back to system find_package.")
                else()
                    message(FATAL_ERROR
                        "[cdpm] Package '${_cdpm_pkg_name}' not found in any loaded repository.\n"
                        "Set CDPM_ALLOW_SYSTEM_PACKAGES=ON to allow a system find_package fallback."
                    )
                endif()
            else()
                cdpm_resolve_version("${_cdpm_pkg_name}" "${_cdpm_meta}" "${_cdpm_req_ver}"
                    _cdpm_version _cdpm_compat)
                cdpm_compute_config_hash("${_cdpm_pkg_name}" "${_cdpm_version}" "${_cdpm_meta}"
                    _cdpm_hash)

                _cdpm_resolve_store_dir(_cdpm_store)
                string(TOLOWER "${_cdpm_pkg_name}" _cdpm_pkg_lc)
                set(_cdpm_install_dir "${_cdpm_store}/${_cdpm_pkg_lc}/${_cdpm_hash}")

                # Lockfile fast-path: when the lockfile pins this package at the freshly recomputed
                # config hash AND the install sentinel is present, trust it and skip the build. The hash
                # is always recomputed (it encodes compilers/toolchain/options/patches), so any change to
                # the build environment moves the hash and forces a rebuild -- the lockfile only ever
                # saves work, it never overrides a changed configuration.
                set(_cdpm_locked FALSE)
                cdpm_lockfile_get("${_cdpm_pkg_name}" _cdpm_lk_found _cdpm_lk_entry)
                if(_cdpm_lk_found)
                    string(JSON _cdpm_lk_hash ERROR_VARIABLE _cdpm_lk_err
                        GET "${_cdpm_lk_entry}" "config_hash")
                    if(NOT _cdpm_lk_err AND _cdpm_lk_hash STREQUAL "${_cdpm_hash}"
                       AND EXISTS "${_cdpm_install_dir}/.cdpm_installed")
                        set(_cdpm_locked TRUE)
                        message(STATUS "[cdpm] ${_cdpm_pkg_lc}@${_cdpm_version} [${_cdpm_hash}] "
                            "locked + installed -- skipping resolve/build.")
                    endif()
                endif()

                if(NOT _cdpm_locked AND NOT EXISTS "${_cdpm_install_dir}/.cdpm_installed")
                    # TODO(roadmap): resolve transitive dependencies before building (host-tool model).
                    cdpm_build_dependency("${_cdpm_pkg_name}" "${_cdpm_version}"
                        "${_cdpm_hash}" "${_cdpm_meta}")
                endif()

                # Record/refresh the resolved package in the lockfile (idempotent canonical write).
                if(NOT _cdpm_locked AND COMMAND cdpm_get_package_source)
                    cdpm_get_package_source("${_cdpm_pkg_name}" "${_cdpm_meta}" "${_cdpm_version}"
                        _cdpm_src _cdpm_dev)
                    cdpm_write_lockfile("${_cdpm_pkg_name}" "${_cdpm_version}" "${_cdpm_hash}"
                        "${_cdpm_src}" "${_cdpm_dev}")
                endif()

                # PROPAGATEd out of the block so the trailing find_package() sees it.
                list(PREPEND CMAKE_PREFIX_PATH "${_cdpm_install_dir}")
            endif()
        endblock()

        # Outside the block: the result variables of this call (<pkg>_FOUND, <pkg>_DIR, imported
        # targets, ...) must be visible to the find_package() that triggered the provider.
        # TODO(roadmap): lockfile fast-path (skip resolve/build when locked + sentinel present).
        if(_cdpm_do_find)
            find_package(${ARGN} BYPASS_PROVIDER)

            if(_cdpm_fp_REQUIRED AND NOT "${_cdpm_install_dir}" STREQUAL ""
               AND NOT ${_cdpm_pkg_name}_FOUND)
                message(FATAL_ERROR
                    "[cdpm] Package '${_cdpm_pkg_name}' was built and installed to "
                    "'${_cdpm_install_dir}', but find_package still could not locate it. "
                    "The package may not ship a usable <name>Config.cmake."
                )
            endif()
        endif()

        # Drop the handful of values PROPAGATEd out of the block (a macro has no scope of its own).
        unset(_cdpm_pkg_name)
        unset(_cdpm_install_dir)
        unset(_cdpm_fp_REQUIRED)
        unset(_cdpm_do_find)
    endif()
endmacro()
