# cdpm_build.cmake - Isolated source resolution and ExternalProject-driven build/install for cdpm.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON helpers, config (source/options/user), toolchain synthesis, config hash.
include(cdpm_utils)
include(cdpm_verange)
include(cdpm_config)
include(cdpm_toolchain)
include(cdpm_hash)
include(cdpm_cps)
include(cdpm_context)

# cdpm root (parent of core/) captured at include time. Driver module paths from the
# registry are relative to this root (e.g. core/bs/cdpm_bs_cmake.cmake).
cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH __CDPM_BUILD_ROOT)
set(__CDPM_BUILD_ROOT "${__CDPM_BUILD_ROOT}" CACHE INTERNAL "cdpm root dir for build drivers")

# .. rst:
# ``_cdpm_cleanup_driver_user_file(<ctx_json>)``
#
# Removes the generated user key-value file from a driver context. Drivers must call this immediately
# before every ``FATAL_ERROR`` so tracked and untracked values do not remain on disk after a failed build.
function(_cdpm_cleanup_driver_user_file ctx_json)
    string(JSON user_file ERROR_VARIABLE user_file_err GET "${ctx_json}" "user_file")
    if(NOT user_file_err AND NOT user_file STREQUAL "")
        file(REMOVE "${user_file}")
    endif()
endfunction()

# .. rst:
# ``cdpm_prepare_source(<pkg_name> <pkg_version> <meta_json> <out_source_json>)``
#
# Resolves the fetch source for ``<pkg_name>`` at ``<pkg_version>`` and returns it as a normalized JSON
# object in ``<out_source_json>`` for the build driver's ``ExternalProject`` step. The source (with the
# version's integrity pin folded in, or a dev override) comes from :cmake:command:`cdpm_get_package_source`;
# this function only normalizes and validates it - the actual download is performed by ExternalProject
# (git clone / URL+hash), keeping target-graph-free isolation.
#
# Output shape by ``type``:
#
# * ``git``   - ``{ "type": "git", "url": ..., "rev": ... }`` (``rev`` pin required);
# * ``url``   - ``{ "type": "url", "url": ..., "sha256": ... }`` (``sha256`` required);
# * ``local`` - ``{ "type": "local", "path": <absolute> }`` (the path must exist; no copy).
function(cdpm_prepare_source pkg_name pkg_version meta_json out_source_json)
    string(TOLOWER "${pkg_name}" name)

    cdpm_get_package_source("${name}" "${meta_json}" "${pkg_version}" src dev)
    string(JSON src_type GET "${src}" "type")

    if(src_type STREQUAL "local")
        string(JSON path ERROR_VARIABLE path_err GET "${src}" "path")
        if(path_err)
            string(JSON path ERROR_VARIABLE path_err GET "${src}" "url")
        endif()
        if(path_err OR path STREQUAL "")
            message(FATAL_ERROR "[cdpm] package '${name}': local source requires a non-empty path.")
        endif()
        if(NOT IS_ABSOLUTE "${path}")
            _cdpm_resolve_project_dir(project_dir)
            cmake_path(ABSOLUTE_PATH path BASE_DIRECTORY "${project_dir}" NORMALIZE OUTPUT_VARIABLE path)
        endif()
        if(NOT EXISTS "${path}")
            message(FATAL_ERROR "[cdpm] package '${name}': local source path does not exist: ${path}")
        endif()
        set(result "{}")
        _cdpm_json_set_safe("${result}" "type" "local" "STRING" result)
        _cdpm_json_set_safe("${result}" "path" "${path}" "STRING" result)
        set(${out_source_json} "${result}")
        return(PROPAGATE ${out_source_json})
    endif()

    if(src_type STREQUAL "git")
        string(JSON url GET "${src}" "url")
        string(JSON rev ERROR_VARIABLE rev_err GET "${src}" "rev")
        string(LENGTH "${rev}" rev_length)
        if(rev_err OR NOT rev_length EQUAL 40 OR NOT rev MATCHES [[^[0-9A-Fa-f]+$]])
            message(FATAL_ERROR "[cdpm] package '${name}': git source requires a full 40-hex 'rev'.")
        endif()
        set(result "{}")
        _cdpm_json_set_safe("${result}" "type" "git" "STRING" result)
        _cdpm_json_set_safe("${result}" "url" "${url}" "STRING" result)
        _cdpm_json_set_safe("${result}" "rev" "${rev}" "STRING" result)
        set(${out_source_json} "${result}")
        return(PROPAGATE ${out_source_json})
    endif()

    if(src_type STREQUAL "url")
        string(JSON url GET "${src}" "url")
        string(JSON sha ERROR_VARIABLE sha_err GET "${src}" "sha256")
        string(LENGTH "${sha}" sha_length)
        if(sha_err OR NOT sha_length EQUAL 64 OR NOT sha MATCHES [[^[0-9A-Fa-f]+$]])
            message(FATAL_ERROR "[cdpm] package '${name}': url source requires 'sha256' as exactly 64 hex "
                "characters.")
        endif()
        set(result "{}")
        _cdpm_json_set_safe("${result}" "type" "url" "STRING" result)
        _cdpm_json_set_safe("${result}" "url" "${url}" "STRING" result)
        _cdpm_json_set_safe("${result}" "sha256" "${sha}" "STRING" result)
        set(${out_source_json} "${result}")
        return(PROPAGATE ${out_source_json})
    endif()

    message(FATAL_ERROR "[cdpm] package '${name}': unsupported source type '${src_type}'.")
endfunction()

# .. rst:
# ``cdpm_collect_patches(<pkg_name> <pkg_version> <meta_json> <out_patches_json>)``
#
# Returns the source patches that apply to ``<pkg_version>`` as a JSON array of *absolute* paths in apply
# order, in ``<out_patches_json>`` (``[]`` when none). The applicable set and its order come from
# :cmake:command:`cdpm_resolve_patch_list` (package-level ``patches[]`` filtered by ``applies_to``/
# ``exclude``, then per-version ``versions.<version>.patches``). Relative paths are project-relative for schema 1
# and manifest-directory-relative with containment checks for schema 2; a missing file is fatal. The build driver uses
# ExternalProject's ``PATCH_COMMAND`` (``git apply``), and their contents already feed the config hash
# (see :cmake:command:`cdpm_compute_config_hash`).
function(cdpm_collect_patches pkg_name pkg_version meta_json out_patches_json)
    string(TOLOWER "${pkg_name}" name)
    set(result "[]")

    cdpm_resolve_patch_list("${meta_json}" "${pkg_version}" specs)
    string(JSON count LENGTH "${specs}")
    if(count EQUAL 0)
        set(${out_patches_json} "${result}")
        return(PROPAGATE ${out_patches_json})
    endif()

    math(EXPR last "${count} - 1")
    foreach(i RANGE 0 ${last})
        string(JSON authored_path GET "${specs}" ${i})
        _cdpm_registry_resolve_patch_path("${name}" "${authored_path}" patch_path)
        if(NOT EXISTS "${patch_path}")
            message(FATAL_ERROR "[cdpm] package '${name}': patch not found: ${patch_path}")
        endif()
        string(JSON result SET "${result}" ${i} "\"${patch_path}\"")
    endforeach()

    set(${out_patches_json} "${result}")
    return(PROPAGATE ${out_patches_json})
endfunction()

# .. rst:
# ``cdpm_build_dependency(<pkg_name> <pkg_version> <config_hash> <meta_json>)``
#
# Builds and installs ``<pkg_name>`` at ``<pkg_version>`` into the store slot
# ``<store>/<pkg_name>/<config_hash>``. Idempotent: if the slot's ``.cdpm_installed`` sentinel exists the
# function returns immediately.
#
# Pipeline: resolve source + collect patches -> prepare wrapper toolchain -> resolve effective options ->
# generate the user key-value include -> dispatch to the package's build-system driver (``build_system``
# member, default ``cmake``) which downloads/patches/configures/builds/installs via ExternalProject ->
# optional CPS generation hook -> write the sentinel. Only the ``cmake`` driver is implemented in v1; any
# other declared driver aborts with a clear "not yet implemented" error from the driver stub.
function(cdpm_build_dependency pkg_name pkg_version config_hash meta_json)
    string(TOLOWER "${pkg_name}" name)

    _cdpm_resolve_store_dir(store)
    _cdpm_resolve_runtime_dir(runtime_dir)
    set(install_dir "${store}/${name}/${config_hash}")

    if(EXISTS "${install_dir}/.cdpm_installed")
        file(REMOVE "${runtime_dir}/user/${name}-${config_hash}.cmake")
        message(STATUS "[cdpm] ${name}@${pkg_version} [${config_hash}] already installed -- skipping.")
        return()
    endif()

    file(MAKE_DIRECTORY "${runtime_dir}")
    if(UNIX)
        file(CHMOD "${runtime_dir}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    endif()

    # ---- Source + patches (downloaded/applied by the driver via ExternalProject) -
    cdpm_prepare_source("${name}" "${pkg_version}" "${meta_json}" source_json)
    cdpm_collect_patches("${name}" "${pkg_version}" "${meta_json}" patches_json)

    # ---- Toolchain --------------------------------------------------------------
    cdpm_prepare_toolchain("${config_hash}" toolchain)

    # ---- Effective options ------------------------------------------------------
    set(options "{}")
    if(COMMAND cdpm_get_package_options)
        cdpm_get_package_options("${name}" "${pkg_version}" options)
    endif()

    # ---- Build directory --------------------------------------------------------
    set(build_dir "${runtime_dir}/bs/${name}-${config_hash}")

    # ---- Select the build-system driver -----------------------------------------
    set(bs "cmake")
    string(JSON bs_decl ERROR_VARIABLE bs_err GET "${meta_json}" "build_system")
    if(NOT bs_err AND NOT bs_decl STREQUAL "")
        string(TOLOWER "${bs_decl}" bs)
    endif()

    cdpm_get_build_system("${bs}" bs_module bs_found)
    if(NOT bs_found)
        message(FATAL_ERROR "[cdpm] package '${name}': unknown build_system '${bs}'.")
    endif()

    set(driver_path "${__CDPM_BUILD_ROOT}/${bs_module}")
    if(NOT EXISTS "${driver_path}")
        message(FATAL_ERROR "[cdpm] package '${name}': build-system driver module not found: "
            "${driver_path}")
    endif()
    include("${driver_path}")

    if(NOT COMMAND cdpm_bs_${bs}_build)
        message(FATAL_ERROR "[cdpm] package '${name}': driver '${bs}' did not define "
            "cdpm_bs_${bs}_build().")
    endif()

    # ---- User key-value file ----------------------------------------------------
    set(user_file "")
    if(COMMAND cdpm_generate_user_file)
        set(user_file "${runtime_dir}/user/${name}-${config_hash}.cmake")
        file(MAKE_DIRECTORY "${runtime_dir}/user")
        if(UNIX)
            file(CHMOD "${runtime_dir}/user" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
        endif()
        cdpm_generate_user_file("${name}" "${user_file}")
        if(UNIX)
            file(CHMOD "${user_file}" PERMISSIONS OWNER_READ OWNER_WRITE)
        endif()
    endif()

    # ---- Assemble the driver context -------------------------------------------
    set(ctx "{}")
    _cdpm_json_set_safe("${ctx}" "build_dir"    "${build_dir}"          "STRING" ctx)
    _cdpm_json_set_safe("${ctx}" "install_dir"  "${install_dir}"        "STRING" ctx)
    string(JSON ctx SET "${ctx}" "source"       "${source_json}")
    string(JSON ctx SET "${ctx}" "patches"      "${patches_json}")
    string(JSON ctx SET "${ctx}" "options"      "${options}")
    _cdpm_json_set_safe("${ctx}" "toolchain"    "${toolchain}"          "STRING" ctx)
    _cdpm_json_set_safe("${ctx}" "build_type"   "${CMAKE_BUILD_TYPE}"   "STRING" ctx)
    _cdpm_json_set_safe("${ctx}" "generator"    "${CMAKE_GENERATOR}"    "STRING" ctx)
    _cdpm_json_set_safe("${ctx}" "prefix_path"  "${CMAKE_PREFIX_PATH}"  "STRING" ctx)
    _cdpm_json_set_safe("${ctx}" "module_path"  "${CMAKE_MODULE_PATH}"  "STRING" ctx)
    _cdpm_json_set_safe("${ctx}" "user_file"    "${user_file}"          "STRING" ctx)

    string(JSON __build_obj ERROR_VARIABLE __build_err GET "${meta_json}" "build")
    if(NOT __build_err)
        string(JSON ctx SET "${ctx}" "build" "${__build_obj}")
    endif()

    message(STATUS "[cdpm] building ${name}@${pkg_version} [${config_hash}] via '${bs}' driver")
    cmake_language(CALL "cdpm_bs_${bs}_build" "${ctx}")

    # The generated file may contain secrets and is needed only during the driver build.
    _cdpm_cleanup_driver_user_file("${ctx}")

    # ---- Optional CPS generation hook (module lands later) ----------------------
    if(COMMAND cdpm_generate_cps_file)
        cdpm_generate_cps_file("${name}" "${pkg_version}" "${install_dir}" "${meta_json}")
    endif()

    # ---- Sentinel ---------------------------------------------------------------
    file(TOUCH "${install_dir}/.cdpm_installed")
    message(STATUS "[cdpm] installed ${name}@${pkg_version} -> ${install_dir}")
endfunction()
