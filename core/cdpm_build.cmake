# cdpm_build.cmake - Isolated source resolution and ExternalProject-driven build/install for cdpm.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON helpers, config (source/options/user), toolchain synthesis, config hash.
include(cdpm_utils)
include(cdpm_config)
include(cdpm_toolchain)
include(cdpm_hash)

# cdpm root (parent of core/) captured at include time. Driver module paths from the
# registry are relative to this root (e.g. core/build/cdpm_bs_cmake.cmake).
cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH __CDPM_BUILD_ROOT)
set(__CDPM_BUILD_ROOT "${__CDPM_BUILD_ROOT}" CACHE INTERNAL "cdpm root dir for build drivers")

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
        string(JSON path GET "${src}" "path")
        if(NOT IS_ABSOLUTE "${path}")
            cmake_path(ABSOLUTE_PATH path BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" NORMALIZE OUTPUT_VARIABLE path)
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
        if(rev_err OR rev STREQUAL "")
            message(FATAL_ERROR "[cdpm] package '${name}': git source requires a pinned 'rev'.")
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
        if(sha_err OR sha STREQUAL "")
            message(FATAL_ERROR "[cdpm] package '${name}': url source requires 'sha256'.")
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
# Returns the declared source patches for ``<pkg_version>`` (``versions.<version>.patches``) as a JSON
# array of *absolute* paths in apply order, in ``<out_patches_json>`` (``[]`` when none). Relative paths are
# resolved against ``CMAKE_SOURCE_DIR``; a missing file is fatal. The patches are applied by the build
# driver via ExternalProject's ``PATCH_COMMAND`` (``git apply``), and their contents already feed the
# config hash (see :cmake:command:`cdpm_compute_config_hash`).
function(cdpm_collect_patches pkg_name pkg_version meta_json out_patches_json)
    string(TOLOWER "${pkg_name}" name)
    set(result "[]")

    if(meta_json STREQUAL "" OR pkg_version STREQUAL "")
        set(${out_patches_json} "${result}")
        return(PROPAGATE ${out_patches_json})
    endif()

    string(JSON patches ERROR_VARIABLE perr GET "${meta_json}" "versions" "${pkg_version}" "patches")
    if(perr OR patches STREQUAL "")
        set(${out_patches_json} "${result}")
        return(PROPAGATE ${out_patches_json})
    endif()
    string(JSON ptype ERROR_VARIABLE terr TYPE "${meta_json}" "versions" "${pkg_version}" "patches")
    if(terr OR NOT ptype STREQUAL "ARRAY")
        set(${out_patches_json} "${result}")
        return(PROPAGATE ${out_patches_json})
    endif()
    string(JSON count LENGTH "${patches}")
    if(count EQUAL 0)
        set(${out_patches_json} "${result}")
        return(PROPAGATE ${out_patches_json})
    endif()

    math(EXPR last "${count} - 1")
    foreach(i RANGE 0 ${last})
        string(JSON patch_path GET "${patches}" ${i})
        if(NOT IS_ABSOLUTE "${patch_path}")
            cmake_path(ABSOLUTE_PATH patch_path BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" NORMALIZE
                OUTPUT_VARIABLE patch_path)
        endif()
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
    set(install_dir "${store}/${name}/${config_hash}")

    if(EXISTS "${install_dir}/.cdpm_installed")
        message(STATUS "[cdpm] ${name}@${pkg_version} [${config_hash}] already installed -- skipping.")
        return()
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

    # ---- User key-value file ----------------------------------------------------
    set(user_file "")
    if(COMMAND cdpm_generate_user_file)
        set(user_file "${CMAKE_BINARY_DIR}/.cdpm/user/${name}-${config_hash}.cmake")
        file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/.cdpm/user")
        cdpm_generate_user_file("${name}" "${user_file}")
    endif()

    # ---- Build directory --------------------------------------------------------
    set(build_dir "${CMAKE_BINARY_DIR}/.cdpm/build/${name}-${config_hash}")

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
    _cdpm_json_set_safe("${ctx}" "user_file"    "${user_file}"          "STRING" ctx)

    message(STATUS "[cdpm] building ${name}@${pkg_version} [${config_hash}] via '${bs}' driver")
    cmake_language(CALL "cdpm_bs_${bs}_build" "${ctx}")

    # ---- Optional CPS generation hook (module lands later) ----------------------
    if(COMMAND cdpm_generate_cps_file)
        cdpm_generate_cps_file("${name}" "${pkg_version}" "${install_dir}" "${meta_json}")
    endif()

    # ---- Sentinel ---------------------------------------------------------------
    file(TOUCH "${install_dir}/.cdpm_installed")
    message(STATUS "[cdpm] installed ${name}@${pkg_version} -> ${install_dir}")
endfunction()
