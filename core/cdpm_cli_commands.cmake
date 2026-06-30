# cdpm_cli_commands.cmake
# Implementation of all cdpm CLI commands. Included by cdpm-cli.cmake and potentially
# by the future cmake provision hook. No platform-specific shell commands -- CMake API only.

cmake_minimum_required(VERSION 3.26)

include(cdpm_version)
# Provides the single _cdpm_resolve_store_dir(<out>) contract, cdpm_config_load and cdpm_load_repos.
# (cdpm_config does not include this module, so there is no include cycle.)
include(cdpm_config)
# Lockfile read/write (cdpm_read_lockfile / cdpm_write_lockfile / cdpm_lockfile_get).
include(cdpm_lockfile)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

set(__CDPM_CLI_BANNER 
[[

 ██████╗██████╗ ██████╗ ███╗   ███╗     ██████╗██╗     ██╗
██╔════╝██╔══██╗██╔══██╗████╗ ████║    ██╔════╝██║     ██║
██║     ██║  ██║██████╔╝██╔████╔██║    ██║     ██║     ██║
██║     ██║  ██║██╔═══╝ ██║╚██╔╝██║    ██║     ██║     ██║
╚██████╗██████╔╝██║     ██║ ╚═╝ ██║    ╚██████╗███████╗██║
 ╚═════╝╚═════╝ ╚═╝     ╚═╝     ╚═╝     ╚═════╝╚══════╝╚═╝
]]
    CACHE INTERNAL "cdpm CLI banner string"
)

# :brief: Prints the cdpm banner to stdout.
function(_cdpm_print_banner)                          
    message(${__CDPM_CLI_BANNER})
endfunction()

# :brief: Collects all installed package entries under the store directory.
# Each element has the form "<pkg_name>|<hash>|<install_dir>".
# :param out_list: output variable name
function(_cdpm_list_installed_packages out_list)
    _cdpm_resolve_store_dir(__store)
    set(__result "")

    if(NOT EXISTS "${__store}")
        set(${out_list} "")
        return(PROPAGATE ${out_list})
    endif()

    file(GLOB __pkg_dirs LIST_DIRECTORIES true "${__store}/*")
    foreach(__pkg_dir IN LISTS __pkg_dirs)
        if(NOT IS_DIRECTORY "${__pkg_dir}")
            continue()
        endif()
        cmake_path(GET __pkg_dir FILENAME __pkg_name)

        file(GLOB __hash_dirs LIST_DIRECTORIES true "${__pkg_dir}/*")
        foreach(__hash_dir IN LISTS __hash_dirs)
            if(NOT IS_DIRECTORY "${__hash_dir}")
                continue()
            endif()
            cmake_path(GET __hash_dir FILENAME __hash)

            if(EXISTS "${__hash_dir}/.cdpm_installed")
                list(APPEND __result "${__pkg_name}|${__hash}|${__hash_dir}")
            endif()
        endforeach()
    endforeach()

    set(${out_list} "${__result}")
    return(PROPAGATE ${out_list})
endfunction()

# :brief: Records a resolved package into the lockfile (idempotent).
#         Resolves the normalized source (with its dev flag) from the package metadata, then writes the
#         entry via cdpm_write_lockfile. Loads the lockfile from lockfile_path on demand. Safe to call on
#         both fresh builds and sentinel-skipped (already-installed) runs.
# :param pkg_name:      package name
# :param pkg_version:   resolved version
# :param config_hash:   resolved config hash
# :param meta_json:     registry metadata for the package
# :param lockfile_path: lockfile path (empty = default ${CMAKE_SOURCE_DIR}/cdpm.lock.json)
function(_cdpm_record_package_lock pkg_name pkg_version config_hash meta_json lockfile_path)
    if(NOT COMMAND cdpm_write_lockfile OR NOT COMMAND cdpm_get_package_source)
        return()
    endif()

    cdpm_get_package_source("${pkg_name}" "${meta_json}" "${pkg_version}" __src __dev)

    if(lockfile_path STREQUAL "")
        cdpm_read_lockfile()
    else()
        cdpm_read_lockfile(PATH "${lockfile_path}")
    endif()
    cdpm_write_lockfile("${pkg_name}" "${pkg_version}" "${config_hash}" "${__src}" "${__dev}")
endfunction()

# ---------------------------------------------------------------------------
# Public commands
# ---------------------------------------------------------------------------

# :brief: Prints usage information for all available CLI commands.
#         Does NOT print the banner -- intended as a standalone info command.
function(cdpm_cmd_help)
    _cdpm_get_version(__ver)
    message("cdpm v${__ver} -- CMake Dependency Provider Manager")
    message([[

Usage:
  cmake -P cdpm-cli.cmake -- [--toolchain <path>] [--generator <name>] <command> [arguments]

Global options (must appear before the command):
  --toolchain <path>               Path to a CMake toolchain file.
                                   Overrides CMAKE_TOOLCHAIN_FILE when both are set.
                                   Affects config-hash computation and child builds.
  --generator <name>               Specify a build system generator.
                                   Overrides CMAKE_GENERATOR when both are set.
                                   Affects config-hash computation and child builds.

Commands:
  help                             Show this help message
  version                          Show cdpm version
  list                             List all installed packages
  info <pkg>                       Show registry metadata for a package
  install <pkg> [<version>]        Build and install a package
  clean <pkg> [<hash>]             Remove installed package(s)
  provision [--lockfile <path>]    Install all packages from a lockfile
  add-registry <path> [--scope machine|project]
                                   Persist a packages.json registry into a config layer
  config blame [<path>]            Show which config layer last set each value

Environment / cache variables:
  CDPM_STORE_DIR                   Override default package store location
  CDPM_ALLOW_SYSTEM_PACKAGES       Fall back to system packages when ON
  CDPM_TOOLSET                     Optional toolset tag included in config hash
  CMAKE_TOOLCHAIN_FILE             Toolchain file fallback (see --toolchain above)
  CMAKE_GENERATOR                  Generator name fallback (see --generator above)
]])
endfunction()

# :brief: Prints the cdpm version string.
function(cdpm_cmd_version)
    _cdpm_get_version(__ver)
    message("cdpm version ${__ver}")
endfunction()

# :brief: Lists all packages currently installed in the store.
function(cdpm_cmd_list)
    _cdpm_print_banner()
    _cdpm_resolve_store_dir(__store)
    message("[cdpm] Store directory: ${__store}")
    message("")

    _cdpm_list_installed_packages(__packages)
    if(__packages STREQUAL "")
        message("[cdpm] No packages installed.")
        return()
    endif()

    message("Installed packages:")
    foreach(__entry IN LISTS __packages)
        string(REPLACE "|" ";" __parts "${__entry}")
        list(GET __parts 0 __pkg)
        list(GET __parts 1 __hash)
        list(GET __parts 2 __dir)
        message("  ${__pkg}  [${__hash}]  ${__dir}")
    endforeach()
    message("")
endfunction()

# :brief: Displays registry metadata for a named package.
# :param pkg_name: package name to look up
function(cdpm_cmd_info pkg_name)
    _cdpm_print_banner()

    if(pkg_name STREQUAL "")
        message(FATAL_ERROR "[cdpm] 'info' requires a package name.")
    endif()

    # Ensure config is loaded so cdpm_find_in_repo() is available.
    if(NOT COMMAND cdpm_config_load)
        message(FATAL_ERROR
            "[cdpm] cdpm_config.cmake is not loaded. "
            "Make sure cdpm-cli.cmake includes it before invoking commands."
        )
    endif()
    cdpm_config_load()
    # Materialize the declared repositories (kind=file|git) into CDPM_MERGED_REPO; without this
    # cdpm_find_in_repo() always misses.
    cdpm_load_repos()

    cdpm_find_in_repo("${pkg_name}" __found __meta_json)
    if(NOT __found)
        message(FATAL_ERROR
            "[cdpm] Package '${pkg_name}' not found in any loaded repository.\n"
            "Declare a registry in cdpm.json (\"repos\": [ { \"kind\": \"file\", \"path\": "
            "\"<.../packages.json>\" } ]) or run 'add-registry <path>'."
        )
    endif()

    message("[cdpm] Metadata for package '${pkg_name}':")
    message("${__meta_json}")
    message("")

    # Show installed instances from store.
    _cdpm_list_installed_packages(__packages)
    set(__found_installed FALSE)
    foreach(__entry IN LISTS __packages)
        string(REPLACE "|" ";" __parts "${__entry}")
        list(GET __parts 0 __pkg)
        if(__pkg STREQUAL "${pkg_name}")
            if(NOT __found_installed)
                message("[cdpm] Installed instances:")
                set(__found_installed TRUE)
            endif()
            list(GET __parts 1 __hash)
            list(GET __parts 2 __dir)
            message("  hash=${__hash}  path=${__dir}")
        endif()
    endforeach()
    if(NOT __found_installed)
        message("[cdpm] Not installed.")
    endif()
    message("")
endfunction()

# :brief: Builds and installs a package into the store.
# :param pkg_name:       package name
# :param pkg_version:    requested version (empty string = use default)
# :param toolchain_file: absolute path to a CMake toolchain file, or empty string.
#                        When non-empty, sets CMAKE_TOOLCHAIN_FILE for this scope so
#                        cdpm_compute_config_hash and cdpm_build_dependency pick it up.
# :param generator:      build system generator name, or empty string. When non-empty, sets
#                        CMAKE_GENERATOR for this scope so the config hash and child build pick it up.
function(cdpm_cmd_install pkg_name pkg_version toolchain_file generator)
    _cdpm_print_banner()

    if(pkg_name STREQUAL "")
        message(FATAL_ERROR "[cdpm] 'install' requires a package name.")
    endif()

    foreach(__cmd IN ITEMS cdpm_config_load cdpm_load_repos cdpm_find_in_repo
                           cdpm_resolve_version cdpm_compute_config_hash
                           cdpm_build_dependency)
        if(NOT COMMAND ${__cmd})
            message(FATAL_ERROR "[cdpm] Required function '${__cmd}' is not available. "
                                "Check that all core modules are included.")
        endif()
    endforeach()

    # Propagate the toolchain into CMAKE_TOOLCHAIN_FILE for this function scope.
    # cdpm_compute_config_hash reads CMAKE_TOOLCHAIN_FILE directly (hashes its content).
    if(NOT toolchain_file STREQUAL "")
        set(CMAKE_TOOLCHAIN_FILE "${toolchain_file}")
    endif()

    # Propagate the generator into CMAKE_GENERATOR for this function scope.
    # cdpm_compute_config_hash reads CMAKE_GENERATOR directly (it is part of the hash inputs).
    if(NOT generator STREQUAL "")
        set(CMAKE_GENERATOR "${generator}")
    endif()

    cdpm_config_load()
    cdpm_load_repos()
    cdpm_find_in_repo("${pkg_name}" __found __meta_json)
    if(NOT __found)
        message(FATAL_ERROR
            "[cdpm] Package '${pkg_name}' not found in any loaded repository.\n"
            "Declare a registry in cdpm.json (\"repos\": [ { \"kind\": \"file\", \"path\": "
            "\"<.../packages.json>\" } ]) or run 'add-registry <path>'."
        )
    endif()

    cdpm_resolve_version("${pkg_name}" "${__meta_json}" "${pkg_version}" __resolved_ver __compat_ver)

    if(NOT toolchain_file STREQUAL "")
        message(STATUS "[cdpm] Toolchain: ${toolchain_file}")
    endif()
    if(NOT generator STREQUAL "")
        message(STATUS "[cdpm] Generator: ${generator}")
    endif()
    message(STATUS "[cdpm] Installing ${pkg_name}@${__resolved_ver} ...")

    cdpm_compute_config_hash("${pkg_name}" "${__resolved_ver}" "${__meta_json}" __hash)
    _cdpm_resolve_store_dir(__store)
    set(__install_dir "${__store}/${pkg_name}/${__hash}")

    if(EXISTS "${__install_dir}/.cdpm_installed")
        message(STATUS "[cdpm] ${pkg_name}@${__resolved_ver} [${__hash}] already installed -- skipping.")
        # Still record the (already-installed) package in the lockfile so the resolved graph is pinned.
        _cdpm_record_package_lock("${pkg_name}" "${__resolved_ver}" "${__hash}" "${__meta_json}" "")
        return()
    endif()

    cdpm_build_dependency("${pkg_name}" "${__resolved_ver}" "${__hash}" "${__meta_json}")
    _cdpm_record_package_lock("${pkg_name}" "${__resolved_ver}" "${__hash}" "${__meta_json}" "")
    message(STATUS "[cdpm] Done: ${pkg_name}@${__resolved_ver} -> ${__install_dir}")
endfunction()

# :brief: Removes installed package artifacts from the store.
#         Removes only the specified build when hash is given, otherwise removes all builds.
# :param pkg_name: package name
# :param pkg_hash: specific config hash to remove (empty string = remove all builds)
function(cdpm_cmd_clean pkg_name pkg_hash)
    _cdpm_print_banner()

    if(pkg_name STREQUAL "")
        message(FATAL_ERROR "[cdpm] 'clean' requires a package name.")
    endif()

    _cdpm_resolve_store_dir(__store)
    set(__pkg_root "${__store}/${pkg_name}")

    if(NOT EXISTS "${__pkg_root}")
        message(STATUS "[cdpm] Nothing to clean for '${pkg_name}'.")
        return()
    endif()

    if(NOT pkg_hash STREQUAL "")
        set(__target "${__pkg_root}/${pkg_hash}")
        if(NOT EXISTS "${__target}")
            message(STATUS "[cdpm] No installation found for '${pkg_name}' [${pkg_hash}].")
            return()
        endif()
        file(REMOVE_RECURSE "${__target}")
        message(STATUS "[cdpm] Removed ${__target}")
    else()
        file(REMOVE_RECURSE "${__pkg_root}")
        message(STATUS "[cdpm] Removed all installations of '${pkg_name}' (${__pkg_root})")
    endif()
endfunction()

# :brief: Reads a lockfile and installs every package listed in it.
# :param lockfile_path:  path to cdpm.lock.json (empty = ${CMAKE_SOURCE_DIR}/cdpm.lock.json)
# :param toolchain_file: absolute path to a CMake toolchain file, or empty string
# :param generator:      build system generator name, or empty string
function(cdpm_cmd_provision lockfile_path toolchain_file generator)
    _cdpm_print_banner()

    if(lockfile_path STREQUAL "")
        set(lockfile_path "${CMAKE_SOURCE_DIR}/cdpm.lock.json")
    endif()

    if(NOT EXISTS "${lockfile_path}")
        message(FATAL_ERROR "[cdpm] Lockfile not found: ${lockfile_path}")
    endif()

    foreach(__cmd IN ITEMS cdpm_config_load cdpm_load_repos cdpm_find_in_repo
                           cdpm_resolve_version cdpm_compute_config_hash
                           cdpm_build_dependency cdpm_read_lockfile cdpm_lockfile_get)
        if(NOT COMMAND ${__cmd})
            message(FATAL_ERROR "[cdpm] Required function '${__cmd}' is not available.")
        endif()
    endforeach()

    # Propagate the toolchain/generator so the recomputed config hash matches the install path.
    if(NOT toolchain_file STREQUAL "")
        set(CMAKE_TOOLCHAIN_FILE "${toolchain_file}")
    endif()
    if(NOT generator STREQUAL "")
        set(CMAKE_GENERATOR "${generator}")
    endif()

    # The lockfile is the authoritative input here: load it (so step-4 version resolution and the
    # fast-path consult it) and enumerate its packages.
    cdpm_read_lockfile(PATH "${lockfile_path}")
    cdpm_config_load()
    cdpm_load_repos()

    get_property(__lock_json GLOBAL PROPERTY CDPM_LOCKFILE_JSON)
    string(JSON __pkg_count ERROR_VARIABLE __err LENGTH "${__lock_json}" "packages")
    if(__err OR __pkg_count EQUAL 0)
        message(STATUS "[cdpm] Lockfile contains no packages.")
        return()
    endif()

    _cdpm_resolve_store_dir(__store)

    math(EXPR __last "${__pkg_count} - 1")
    foreach(__i RANGE 0 ${__last})
        string(JSON __pkg_name ERROR_VARIABLE __err MEMBER "${__lock_json}" "packages" ${__i})
        if(__err)
            message(WARNING "[cdpm] provision: cannot read package index ${__i} -- ${__err}")
            continue()
        endif()

        cdpm_find_in_repo("${__pkg_name}" __found __meta_json)
        if(NOT __found)
            message(WARNING "[cdpm] provision: '${__pkg_name}' is not in any loaded repository -- skipping.")
            continue()
        endif()

        cdpm_resolve_version("${__pkg_name}" "${__meta_json}" "" __resolved_ver __compat_ver)
        cdpm_compute_config_hash("${__pkg_name}" "${__resolved_ver}" "${__meta_json}" __hash)
        set(__install_dir "${__store}/${__pkg_name}/${__hash}")

        # Fast-path: lockfile pins this hash AND the sentinel exists -> nothing to do.
        cdpm_lockfile_get("${__pkg_name}" __lk_found __lk_entry)
        set(__locked FALSE)
        if(__lk_found)
            string(JSON __lk_hash ERROR_VARIABLE __lk_err GET "${__lk_entry}" "config_hash")
            if(NOT __lk_err AND __lk_hash STREQUAL "${__hash}"
               AND EXISTS "${__install_dir}/.cdpm_installed")
                set(__locked TRUE)
            endif()
        endif()

        if(__locked)
            message(STATUS "[cdpm] ${__pkg_name}@${__resolved_ver} [${__hash}] locked + installed -- skipping.")
            continue()
        endif()

        message(STATUS "[cdpm] Provisioning ${__pkg_name}@${__resolved_ver} [${__hash}] ...")
        cdpm_build_dependency("${__pkg_name}" "${__resolved_ver}" "${__hash}" "${__meta_json}")
        _cdpm_record_package_lock("${__pkg_name}" "${__resolved_ver}" "${__hash}" "${__meta_json}"
            "${lockfile_path}")
    endforeach()

    message(STATUS "[cdpm] Provision complete.")
endfunction()

# :brief: Persists a ``kind: file`` registry entry into a config layer that cdpm_config_load() reads.
#         Appends ``{ "kind": "file", "path": "<abs>" }`` to the target file's ``repos[]`` array so the
#         registry survives across CLI invocations (cmake -P script mode keeps no cache) and is actually
#         consumed by cdpm_load_repos(). The registry path is stored absolute, which is CWD-independent.
# :param registry_path: path to a packages.json file (resolved to an absolute path)
# :param scope:         'machine' (~/.cdpm/config.json) or 'project' (${CMAKE_SOURCE_DIR}/cdpm.json).
#                       The target file mirrors cdpm_config_load()'s layer-path resolution, so the
#                       CDPM_MACHINE_CONFIG / CDPM_PROJECT_CONFIG overrides apply identically.
function(cdpm_cmd_add_registry registry_path scope)
    _cdpm_print_banner()

    if(registry_path STREQUAL "")
        message(FATAL_ERROR "[cdpm] 'add-registry' requires a path to a packages.json file.")
    endif()

    if(NOT EXISTS "${registry_path}")
        message(WARNING "[cdpm] Registry file does not exist (yet): ${registry_path}")
    endif()

    cmake_path(ABSOLUTE_PATH registry_path NORMALIZE OUTPUT_VARIABLE abs_path)

    # Resolve the target config file, mirroring cdpm_config_load()'s layer-path resolution so we write
    # exactly the file the loader reads (and so the *_CONFIG cache overrides make this testable).
    if(scope STREQUAL "machine")
        if(DEFINED CDPM_MACHINE_CONFIG)
            set(target "${CDPM_MACHINE_CONFIG}")
        else()
            set(target "$ENV{HOME}/.cdpm/config.json")
        endif()
    elseif(scope STREQUAL "project")
        if(DEFINED CDPM_PROJECT_CONFIG)
            set(target "${CDPM_PROJECT_CONFIG}")
        else()
            set(target "${CMAKE_SOURCE_DIR}/cdpm.json")
        endif()
    else()
        message(FATAL_ERROR "[cdpm] add-registry: unknown scope '${scope}' (expected machine|project).")
    endif()

    # Load the existing config (must be a JSON object) or seed a fresh schema-1 document.
    if(EXISTS "${target}")
        file(READ "${target}" config_json)
        string(JSON config_type ERROR_VARIABLE type_err TYPE "${config_json}")
        if(type_err OR NOT config_type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] add-registry: config file '${target}' is not a JSON object.")
        endif()
    else()
        set(config_json [=[{"cdpm_schema":1,"repos":[]}]=])
    endif()

    # Ensure a repos[] array exists to append into.
    string(JSON repos ERROR_VARIABLE repos_err GET "${config_json}" "repos")
    if(repos_err)
        set(repos "[]")
    endif()

    # Dedup: a file entry pointing at the same absolute path is a no-op.
    string(JSON repos_len ERROR_VARIABLE len_err LENGTH "${repos}")
    if(NOT len_err AND repos_len GREATER 0)
        math(EXPR repos_last "${repos_len} - 1")
        foreach(i RANGE 0 ${repos_last})
            string(JSON entry GET "${repos}" ${i})
            string(JSON entry_kind ERROR_VARIABLE k_err GET "${entry}" "kind")
            string(JSON entry_path ERROR_VARIABLE p_err GET "${entry}" "path")
            if(NOT k_err AND NOT p_err AND entry_kind STREQUAL "file" AND entry_path STREQUAL "${abs_path}")
                message(STATUS "[cdpm] Registry already present in ${target}: ${abs_path}")
                return()
            endif()
        endforeach()
    else()
        set(repos_len 0)
    endif()

    # Build the new entry { "kind": "file", "path": "<abs>" } with proper JSON escaping.
    set(new_entry "{}")
    _cdpm_json_set_safe("${new_entry}" "kind" "file" "STRING" new_entry)
    _cdpm_json_set_safe("${new_entry}" "path" "${abs_path}" "STRING" new_entry)

    # Append the entry and write the updated repos[] back into the config document.
    string(JSON repos SET "${repos}" ${repos_len} "${new_entry}")
    string(JSON config_json SET "${config_json}" "repos" "${repos}")

    cmake_path(GET target PARENT_PATH target_dir)
    file(MAKE_DIRECTORY "${target_dir}")
    file(WRITE "${target}" "${config_json}\n")

    message(STATUS "[cdpm] Registry added to ${scope} config: ${target}")
    message(STATUS "[cdpm] repos[] entry: { kind: file, path: ${abs_path} }")
endfunction()

# :brief: Reports which config layer last set each tracked path (CLI wrapper over cdpm_config_blame).
# :param path:   optional dotted path; empty string blames every tracked path
# :param OUTPUT: optional variable name; when given, the flat `path;label;...` list is returned in the
#                parent scope and nothing is printed (no banner) -- mirrors cdpm_config_blame and makes
#                the command strictly testable. Without OUTPUT the result is printed via message(STATUS).
function(cdpm_cmd_config_blame path)
    cmake_parse_arguments(arg "" "OUTPUT" "" ${ARGN})

    foreach(__cmd IN ITEMS cdpm_config_load cdpm_config_blame)
        if(NOT COMMAND ${__cmd})
            message(FATAL_ERROR
                "[cdpm] cdpm_config.cmake is not loaded. "
                "Make sure cdpm-cli.cmake includes it before invoking 'config blame'."
            )
        endif()
    endforeach()

    cdpm_config_load()

    if(path STREQUAL "")
        cdpm_config_blame(OUTPUT __blame)
    else()
        cdpm_config_blame(PATH "${path}" OUTPUT __blame)
    endif()

    # Quiet mode: return the flat list, print nothing (no banner).
    if(DEFINED arg_OUTPUT)
        set(${arg_OUTPUT} "${__blame}")
        return(PROPAGATE ${arg_OUTPUT})
    endif()

    _cdpm_print_banner()

    list(LENGTH __blame __n)
    if(__n EQUAL 0)
        message(STATUS "[cdpm] config blame: no recorded origins.")
        return()
    endif()

    message("[cdpm] Config blame (which layer last set each value):")
    math(EXPR __pairs "${__n} / 2 - 1")
    foreach(__p RANGE 0 ${__pairs})
        math(EXPR __ki "${__p} * 2")
        math(EXPR __li "${__ki} + 1")
        list(GET __blame ${__ki} __k)
        list(GET __blame ${__li} __l)
        message("  ${__k} <- ${__l}")
    endforeach()
    message("")
endfunction()
