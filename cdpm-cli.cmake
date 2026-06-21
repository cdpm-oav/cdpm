# cdpm-cli.cmake
# Entry point for the cdpm command-line interface.
#
# Usage:
#   cmake -P cdpm-cli.cmake -- [--toolchain <path>] [--generator <path>] <command> [arguments]
#
# cmake -P passes arguments through CMAKE_ARGV<N>:
#   CMAKE_ARGV0 = cmake executable path
#   CMAKE_ARGV1 = -P
#   CMAKE_ARGV2 = path/to/cdpm-cli.cmake
#   CMAKE_ARGV3 = --              (separator)
#   CMAKE_ARGV4 = [--toolchain]   (optional global option or command)
#   CMAKE_ARGV5 = ...

cmake_minimum_required(VERSION 3.26)

# ---------------------------------------------------------------------------
# Locate the cdpm root directory (directory containing this script).
# ---------------------------------------------------------------------------
cmake_path(GET CMAKE_CURRENT_LIST_FILE PARENT_PATH __CDPM_ROOT)

# Add cdpm modules path as first path to find
list(PREPEND CMAKE_MODULE_PATH "${__CDPM_ROOT}/core")

# ---------------------------------------------------------------------------
# Include core modules.
# ---------------------------------------------------------------------------
include(cdpm_cli_commands)

# cdpm_config.cmake is optional at this stage: it may not exist yet while the
# module is being scaffolded.  Commands that need it check internally.
set(__CDPM_CONFIG_MODULE "${__CDPM_ROOT}/core/cdpm_config.cmake")
if(EXISTS "${__CDPM_CONFIG_MODULE}")
    include("${__CDPM_CONFIG_MODULE}")
endif()

set(__CDPM_HASH_MODULE "${__CDPM_ROOT}/core/cdpm_hash.cmake")
if(EXISTS "${__CDPM_HASH_MODULE}")
    include("${__CDPM_HASH_MODULE}")
endif()

set(__CDPM_BUILD_MODULE "${__CDPM_ROOT}/core/cdpm_build.cmake")
if(EXISTS "${__CDPM_BUILD_MODULE}")
    include("${__CDPM_BUILD_MODULE}")
endif()

# ---------------------------------------------------------------------------
# Parse CLI arguments from CMAKE_ARGV<N>.
#
# Argument layout when invoked as:
#   cmake -P cdpm-cli.cmake -- cmd arg1 arg2
# is:
#   CMAKE_ARGC = 6
#   CMAKE_ARGV0 = cmake
#   CMAKE_ARGV1 = -P
#   CMAKE_ARGV2 = cdpm-cli.cmake
#   CMAKE_ARGV3 = --
#   CMAKE_ARGV4 = cmd
#   CMAKE_ARGV5 = arg1
#   CMAKE_ARGV6 = arg2
#
# The '--' separator is mandatory; arguments before it are ignored.
# ---------------------------------------------------------------------------

# Find the index of '--' in CMAKE_ARGV.
set(__CDPM_ARGS_START -1)
set(__CDPM_SCAN_IDX 3)
while(__CDPM_SCAN_IDX LESS "${CMAKE_ARGC}")
    if("${CMAKE_ARGV${__CDPM_SCAN_IDX}}" STREQUAL "--")
        math(EXPR __CDPM_ARGS_START "${__CDPM_SCAN_IDX} + 1")
        break()
    endif()
    math(EXPR __CDPM_SCAN_IDX "${__CDPM_SCAN_IDX} + 1")
endwhile()

# Collect user arguments into CDPM_CLI_ARGS.
set(CDPM_CLI_ARGS "")
if(__CDPM_ARGS_START GREATER 0)
    set(__CDPM_IDX "${__CDPM_ARGS_START}")
    while(__CDPM_IDX LESS "${CMAKE_ARGC}")
        list(APPEND CDPM_CLI_ARGS "${CMAKE_ARGV${__CDPM_IDX}}")
        math(EXPR __CDPM_IDX "${__CDPM_IDX} + 1")
    endwhile()
endif()

# ---------------------------------------------------------------------------
# Resolve effective toolchain path.
#
# Priority: --toolchain <path> CLI option > CMAKE_TOOLCHAIN_FILE variable > empty.
# The resolved path is stored in CDPM_EFFECTIVE_TOOLCHAIN and also written back
# into CMAKE_TOOLCHAIN_FILE so downstream core modules see a consistent value.
# ---------------------------------------------------------------------------
set(CDPM_EFFECTIVE_TOOLCHAIN "")

# Strip --toolchain <path> from CDPM_CLI_ARGS if present (it is a global option,
# not a positional command argument).
set(__CDPM_CLEAN_ARGS "")
list(LENGTH CDPM_CLI_ARGS __CDPM_NARGS)
set(__CDPM_GOPT_IDX 0)
while(__CDPM_GOPT_IDX LESS "${__CDPM_NARGS}")
    list(GET CDPM_CLI_ARGS ${__CDPM_GOPT_IDX} __CDPM_GOPT_TOKEN)
    if(__CDPM_GOPT_TOKEN STREQUAL "--toolchain")
        math(EXPR __CDPM_GOPT_NEXT "${__CDPM_GOPT_IDX} + 1")
        if(__CDPM_GOPT_NEXT LESS "${__CDPM_NARGS}")
            list(GET CDPM_CLI_ARGS ${__CDPM_GOPT_NEXT} CDPM_EFFECTIVE_TOOLCHAIN)
            # Advance past the value token.
            math(EXPR __CDPM_GOPT_IDX "${__CDPM_GOPT_IDX} + 2")
        else()
            message(FATAL_ERROR "[cdpm] '--toolchain' requires a path argument.")
        endif()
    else()
        list(APPEND __CDPM_CLEAN_ARGS "${__CDPM_GOPT_TOKEN}")
        math(EXPR __CDPM_GOPT_IDX "${__CDPM_GOPT_IDX} + 1")
    endif()
endwhile()
set(CDPM_CLI_ARGS "${__CDPM_CLEAN_ARGS}")
unset(__CDPM_CLEAN_ARGS)
unset(__CDPM_GOPT_IDX)
unset(__CDPM_GOPT_TOKEN)

# Fall back to CMAKE_TOOLCHAIN_FILE if --toolchain was not supplied.
if(CDPM_EFFECTIVE_TOOLCHAIN STREQUAL "" AND DEFINED CMAKE_TOOLCHAIN_FILE
   AND NOT CMAKE_TOOLCHAIN_FILE STREQUAL "")
    set(CDPM_EFFECTIVE_TOOLCHAIN "${CMAKE_TOOLCHAIN_FILE}")
endif()

# Validate the resolved path when non-empty.
if(NOT CDPM_EFFECTIVE_TOOLCHAIN STREQUAL "")
    cmake_path(ABSOLUTE_PATH CDPM_EFFECTIVE_TOOLCHAIN NORMALIZE
               OUTPUT_VARIABLE CDPM_EFFECTIVE_TOOLCHAIN)
    if(NOT EXISTS "${CDPM_EFFECTIVE_TOOLCHAIN}")
        message(FATAL_ERROR
            "[cdpm] Toolchain file does not exist: ${CDPM_EFFECTIVE_TOOLCHAIN}")
    endif()
    # Make the resolved path visible to core modules as CMAKE_TOOLCHAIN_FILE.
    set(CMAKE_TOOLCHAIN_FILE "${CDPM_EFFECTIVE_TOOLCHAIN}")
endif()

# ---------------------------------------------------------------------------
# Dispatch command.
# ---------------------------------------------------------------------------
list(LENGTH CDPM_CLI_ARGS __CDPM_NARGS)

if(__CDPM_NARGS EQUAL 0)
    cdpm_cmd_help()
    return()
endif()

list(GET CDPM_CLI_ARGS 0 __CDPM_COMMAND)

# ---- help -----------------------------------------------------------------
if(__CDPM_COMMAND STREQUAL "help")
    cdpm_cmd_help()

# ---- version --------------------------------------------------------------
elseif(__CDPM_COMMAND STREQUAL "version")
    cdpm_cmd_version()

# ---- list -----------------------------------------------------------------
elseif(__CDPM_COMMAND STREQUAL "list")
    cdpm_cmd_list()

# ---- info <pkg> -----------------------------------------------------------
elseif(__CDPM_COMMAND STREQUAL "info")
    if(__CDPM_NARGS LESS 2)
        message(FATAL_ERROR "[cdpm] 'info' requires a package name.\n"
                            "Usage: cmake -P cdpm-cli.cmake -- info <package>")
    endif()
    list(GET CDPM_CLI_ARGS 1 __CDPM_PKG)
    cdpm_cmd_info("${__CDPM_PKG}")

# ---- install <pkg> [<version>] --------------------------------------------
elseif(__CDPM_COMMAND STREQUAL "install")
    if(__CDPM_NARGS LESS 2)
        message(FATAL_ERROR "[cdpm] 'install' requires a package name.\n"
                            "Usage: cmake -P cdpm-cli.cmake -- [--toolchain <path>] install <package> [<version>]")
    endif()
    list(GET CDPM_CLI_ARGS 1 __CDPM_PKG)

    set(__CDPM_VER "")
    if(__CDPM_NARGS GREATER_EQUAL 3)
        list(GET CDPM_CLI_ARGS 2 __CDPM_VER)
    endif()

    cdpm_cmd_install("${__CDPM_PKG}" "${__CDPM_VER}" "${CDPM_EFFECTIVE_TOOLCHAIN}")

# ---- clean <pkg> [<hash>] -------------------------------------------------
elseif(__CDPM_COMMAND STREQUAL "clean")
    if(__CDPM_NARGS LESS 2)
        message(FATAL_ERROR "[cdpm] 'clean' requires a package name.\n"
                            "Usage: cmake -P cdpm-cli.cmake -- clean <package> [<hash>]")
    endif()
    list(GET CDPM_CLI_ARGS 1 __CDPM_PKG)

    set(__CDPM_HASH "")
    if(__CDPM_NARGS GREATER_EQUAL 3)
        list(GET CDPM_CLI_ARGS 2 __CDPM_HASH)
    endif()

    cdpm_cmd_clean("${__CDPM_PKG}" "${__CDPM_HASH}")

# ---- provision [--lockfile <path>] ----------------------------------------
elseif(__CDPM_COMMAND STREQUAL "provision")
    set(__CDPM_LOCKFILE "")

    # Parse optional --lockfile <path> argument.
    set(__CDPM_PROV_IDX 1)
    while(__CDPM_PROV_IDX LESS "${__CDPM_NARGS}")
        list(GET CDPM_CLI_ARGS ${__CDPM_PROV_IDX} __CDPM_PROV_TOKEN)
        if(__CDPM_PROV_TOKEN STREQUAL "--lockfile")
            math(EXPR __CDPM_PROV_NEXT "${__CDPM_PROV_IDX} + 1")
            if(__CDPM_PROV_NEXT LESS "${__CDPM_NARGS}")
                list(GET CDPM_CLI_ARGS ${__CDPM_PROV_NEXT} __CDPM_LOCKFILE)
            else()
                message(FATAL_ERROR "[cdpm] '--lockfile' requires a path argument.")
            endif()
        endif()
        math(EXPR __CDPM_PROV_IDX "${__CDPM_PROV_IDX} + 1")
    endwhile()

    cdpm_cmd_provision("${__CDPM_LOCKFILE}" "${CDPM_EFFECTIVE_TOOLCHAIN}")

# ---- add-registry <path> --------------------------------------------------
elseif(__CDPM_COMMAND STREQUAL "add-registry")
    if(__CDPM_NARGS LESS 2)
        message(FATAL_ERROR "[cdpm] 'add-registry' requires a registry path.\n"
                            "Usage: cmake -P cdpm-cli.cmake -- add-registry <path/to/packages.json>")
    endif()
    list(GET CDPM_CLI_ARGS 1 __CDPM_REG_PATH)
    cdpm_cmd_add_registry("${__CDPM_REG_PATH}")

# ---- unknown command ------------------------------------------------------
else()
    message(FATAL_ERROR
        "[cdpm] Unknown command: '${__CDPM_COMMAND}'\n"
        "Run 'cmake -P cdpm-cli.cmake -- help' to see available commands."
    )
endif()
