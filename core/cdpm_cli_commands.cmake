# cdpm_cli_commands.cmake
# Implementation of all cdpm CLI commands. Included by cdpm-cli.cmake and potentially
# by the future cmake provision hook. No platform-specific shell commands -- CMake API only.

cmake_minimum_required(VERSION 3.26)

include(cdpm_version)

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

# :brief: Resolves CDPM_STORE_DIR: ENV override > platform default > binary-dir fallback.
# Sets __CDPM_RESOLVED_STORE_DIR in parent scope.
function(_cdpm_resolve_store_dir)
    if(DEFINED CDPM_STORE_DIR AND NOT CDPM_STORE_DIR STREQUAL "")
        set(__CDPM_RESOLVED_STORE_DIR "${CDPM_STORE_DIR}" PARENT_SCOPE)
        return()
    endif()

    if(DEFINED ENV{CDPM_STORE_DIR} AND NOT "$ENV{CDPM_STORE_DIR}" STREQUAL "")
        set(__CDPM_RESOLVED_STORE_DIR "$ENV{CDPM_STORE_DIR}" PARENT_SCOPE)
        return()
    endif()

    if(WIN32)
        if(DEFINED ENV{LOCALAPPDATA} AND NOT "$ENV{LOCALAPPDATA}" STREQUAL "")
            set(__CDPM_RESOLVED_STORE_DIR "$ENV{LOCALAPPDATA}/.cdpm/store" PARENT_SCOPE)
        else()
            set(__CDPM_RESOLVED_STORE_DIR "${CMAKE_BINARY_DIR}/_cdpm/store" PARENT_SCOPE)
        endif()
    else()
        if(DEFINED ENV{HOME} AND NOT "$ENV{HOME}" STREQUAL "")
            set(__CDPM_RESOLVED_STORE_DIR "$ENV{HOME}/.cdpm/store" PARENT_SCOPE)
        else()
            set(__CDPM_RESOLVED_STORE_DIR "${CMAKE_BINARY_DIR}/_cdpm/store" PARENT_SCOPE)
        endif()
    endif()
endfunction()

# :brief: Collects all installed package entries under the store directory.
# Each element has the form "<pkg_name>|<hash>|<install_dir>".
# :param out_list: output variable name
function(_cdpm_list_installed_packages out_list)
    _cdpm_resolve_store_dir()
    set(__result "")

    if(NOT EXISTS "${__CDPM_RESOLVED_STORE_DIR}")
        set(${out_list} "" PARENT_SCOPE)
        return()
    endif()

    file(GLOB __pkg_dirs LIST_DIRECTORIES true "${__CDPM_RESOLVED_STORE_DIR}/*")
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

    set(${out_list} "${__result}" PARENT_SCOPE)
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
  add-registry <path>              Register an additional packages.json path
  config blame [<path>]            Show which config layer last set each value

Environment / cache variables:
  CDPM_STORE_DIR                   Override default package store location
  CDPM_REGISTRY_FILES              Semicolon-separated list of registry paths
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
    _cdpm_resolve_store_dir()
    message("[cdpm] Store directory: ${__CDPM_RESOLVED_STORE_DIR}")
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

    cdpm_find_in_repo("${pkg_name}" __found __meta_json)
    if(NOT __found)
        message(FATAL_ERROR "[cdpm] Package '${pkg_name}' not found in any loaded repository.")
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

    foreach(__cmd IN ITEMS cdpm_config_load cdpm_find_in_repo
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
    cdpm_find_in_repo("${pkg_name}" __found __meta_json)
    if(NOT __found)
        message(FATAL_ERROR "[cdpm] Package '${pkg_name}' not found in any loaded repository.")
    endif()

    cdpm_resolve_version("${pkg_name}" "${__meta_json}" "${pkg_version}" __resolved_ver)

    if(NOT toolchain_file STREQUAL "")
        message(STATUS "[cdpm] Toolchain: ${toolchain_file}")
    endif()
    if(NOT generator STREQUAL "")
        message(STATUS "[cdpm] Generator: ${generator}")
    endif()
    message(STATUS "[cdpm] Installing ${pkg_name}@${__resolved_ver} ...")

    cdpm_compute_config_hash("${pkg_name}" "${__resolved_ver}" "${__meta_json}" __hash)
    _cdpm_resolve_store_dir()
    set(__install_dir "${__CDPM_RESOLVED_STORE_DIR}/${pkg_name}/${__hash}")

    if(EXISTS "${__install_dir}/.cdpm_installed")
        message(STATUS "[cdpm] ${pkg_name}@${__resolved_ver} [${__hash}] already installed -- skipping.")
        return()
    endif()

    cdpm_build_dependency("${pkg_name}" "${__resolved_ver}" "${__hash}" "${__meta_json}")
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

    _cdpm_resolve_store_dir()
    set(__pkg_root "${__CDPM_RESOLVED_STORE_DIR}/${pkg_name}")

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

    foreach(__cmd IN ITEMS cdpm_config_load cdpm_find_in_repo
                           cdpm_resolve_version cdpm_compute_config_hash
                           cdpm_build_dependency)
        if(NOT COMMAND ${__cmd})
            message(FATAL_ERROR "[cdpm] Required function '${__cmd}' is not available.")
        endif()
    endforeach()

    file(READ "${lockfile_path}" __lock_json)
    cdpm_config_load()

    # Enumerate packages listed in the lockfile.
    string(JSON __pkg_count ERROR_VARIABLE __err LENGTH "${__lock_json}" "packages")
    if(__err OR __pkg_count EQUAL 0)
        message(STATUS "[cdpm] Lockfile contains no packages.")
        return()
    endif()

    math(EXPR __last "${__pkg_count} - 1")
    foreach(__i RANGE 0 ${__last})
        string(JSON __pkg_name ERROR_VARIABLE __err MEMBER "${__lock_json}" "packages" ${__i})
        if(__err)
            message(WARNING "[cdpm] provision: cannot read package index ${__i} -- ${__err}")
            continue()
        endif()

        string(JSON __locked_ver ERROR_VARIABLE __err GET "${__lock_json}" "packages" "${__pkg_name}" "version")
        if(__err)
            set(__locked_ver "")
        endif()

        message(STATUS "[cdpm] Provisioning ${__pkg_name}@${__locked_ver} ...")
        cdpm_cmd_install("${__pkg_name}" "${__locked_ver}" "${toolchain_file}" "${generator}")
    endforeach()

    message(STATUS "[cdpm] Provision complete.")
endfunction()

# :brief: Appends a registry file path to CDPM_REGISTRY_FILES cache variable.
# :param registry_path: absolute or relative path to a packages.json file
function(cdpm_cmd_add_registry registry_path)
    _cdpm_print_banner()

    if(registry_path STREQUAL "")
        message(FATAL_ERROR "[cdpm] 'add-registry' requires a path to a packages.json file.")
    endif()

    if(NOT EXISTS "${registry_path}")
        message(WARNING "[cdpm] Registry file does not exist (yet): ${registry_path}")
    endif()

    cmake_path(ABSOLUTE_PATH registry_path NORMALIZE OUTPUT_VARIABLE __abs_path)

    if(DEFINED CDPM_REGISTRY_FILES)
        list(FIND CDPM_REGISTRY_FILES "${__abs_path}" __idx)
        if(NOT __idx EQUAL -1)
            message(STATUS "[cdpm] Registry already registered: ${__abs_path}")
            return()
        endif()
        list(APPEND CDPM_REGISTRY_FILES "${__abs_path}")
    else()
        set(CDPM_REGISTRY_FILES "${__abs_path}")
    endif()

    set(CDPM_REGISTRY_FILES "${CDPM_REGISTRY_FILES}"
        CACHE STRING "Semicolon-separated list of cdpm registry (packages.json) paths" FORCE)

    message(STATUS "[cdpm] Registry added: ${__abs_path}")
    message(STATUS "[cdpm] CDPM_REGISTRY_FILES = ${CDPM_REGISTRY_FILES}")
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
        set(${arg_OUTPUT} "${__blame}" PARENT_SCOPE)
        return()
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
