# cdpm_basics.cmake - Shared foundation for cdpm: root paths, common options, path resolution,
# toolchain freeze constants and small cross-module primitives.
#
# This is the lowest internal layer. It depends only on standard CMake modules and cdpm_json; it must
# never include a functional module (config, registry, resolver, build, lockfile, toolchain). Every other
# core module includes this one for the shared basis it owns.

include_guard(GLOBAL)

cmake_policy(VERSION 3.25...4.0)

include(cdpm_json) # JSON helpers shared across modules.

# =============================================================================
# Root paths
# =============================================================================

# .. rst:
# ``__CDPM_CORE_DIR`` / ``__CDPM_ROOT``
#
# Canonical locations captured once at include time: ``__CDPM_CORE_DIR`` is this module's directory
# (``cdpm/core``) and ``__CDPM_ROOT`` its parent (the cdpm tree root that holds ``cdpm.cmake``). Consumers
# that used to recompute these from ``CMAKE_CURRENT_LIST_DIR`` in their own module scope read them here
# instead, so build drivers, the orchestrator, the registry validator and the version loader all agree on
# one root. They are INTERNAL cache entries because a core module may first include this module from inside
# a function: ordinary variables would disappear with that function scope while ``include_guard(GLOBAL)``
# would prevent them from being initialized again.
block(SCOPE_FOR VARIABLES 
    PROPAGATE __CDPM_ROOT __CDPM_CORE_DIR
)
    set(__CDPM_CORE_DIR "${CMAKE_CURRENT_LIST_DIR}" CACHE INTERNAL "cdpm core module directory" FORCE)
    cmake_path(GET __CDPM_CORE_DIR PARENT_PATH cdpm_root)
    set(__CDPM_ROOT "${cdpm_root}" CACHE INTERNAL "cdpm root directory" FORCE)
endblock()

# =============================================================================
# Global options & cross-module cache variables
# =============================================================================

# Provider behaviour switches (consumed by cdpm_provide_dependency and the orchestrator forwarding).
option(CDPM_DISABLE "Disable cdpm provider")
option(CDPM_BYPASS "Bypass all `find_package` calls into cmake default implementation")
option(CDPM_ALLOW_SYSTEM_PACKAGES "Fall back to a system find_package when a package is absent from the registry")

include(CMakeDependentOption)

# CPS descriptor generation is only meaningful where CMake's find_package can read the emitted revision.
cmake_dependent_option(CDPM_GENERATE_CPS
    "Generate CPS package descriptors after successful install"
    ON "CMAKE_VERSION VERSION_GREATER_EQUAL 4.3" OFF
)

# Cache root for downloaded archives and other reusable artifacts. In library mode this defaults under the
# consumer's build tree; script/CLI contexts without CMAKE_BINARY_DIR fall back at resolution time.
if(DEFINED CMAKE_BINARY_DIR AND NOT CMAKE_BINARY_DIR STREQUAL "")
    set(CDPM_CACHE_PATH "${CMAKE_BINARY_DIR}/.cdpm" CACHE PATH "cdpm cache root directory path")
endif()

# .. rst:
# Cross-module override variables (documented here; created by their owners or the caller). Empty-vs-unset
# semantics differ per group:
#
# * ``CDPM_PROJECT_DIR`` / ``CDPM_RUNTIME_DIR`` / ``CDPM_STORE_DIR`` / ``CDPM_CACHE_PATH`` /
#   ``CDPM_LOCKFILE_PATH`` - empty means "use the default"; a non-empty value overrides it.
# * ``CDPM_MACHINE_CONFIG`` / ``CDPM_PROJECT_CONFIG`` / ``CDPM_USER_CONFIG`` - tri-state: *undefined* keeps
#   the conventional default, defined-empty disables the layer, defined-non-empty overrides the path. These
#   must never be pre-seeded as empty cache entries or an absent setting would silently disable the layer.
# * ``CDPM_TOOLCHAIN_VARS`` - extra toolchain variables frozen into wrapper toolchains (see the freeze
#   allow-list below).
# * ``CDPM_TOOLSET`` - optional toolset tag folded into the config hash.
# * ``CDPM_SKIP_LOCKFILE`` - ignore lockfile pins for the current invocation.
# * ``CDPM_CONFIG_TRACE`` - emit per-layer config diagnostics.

# =============================================================================
# Project / runtime / store / cache path resolution
# =============================================================================

# .. rst:
# ``_cdpm_resolve_project_dir(<out_dir>)``
#
# Returns the normalized project directory. ``CDPM_PROJECT_DIR`` overrides the library default
# ``CMAKE_SOURCE_DIR``; a relative override is interpreted from that default.
function(_cdpm_resolve_project_dir out_dir)
    if(DEFINED CDPM_PROJECT_DIR AND NOT CDPM_PROJECT_DIR STREQUAL "")
        set(dir "${CDPM_PROJECT_DIR}")
    else()
        set(dir "${CMAKE_SOURCE_DIR}")
    endif()
    cmake_path(ABSOLUTE_PATH dir BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" NORMALIZE OUTPUT_VARIABLE dir)
    set(${out_dir} "${dir}")
    return(PROPAGATE ${out_dir})
endfunction()

# .. rst:
# ``_cdpm_resolve_runtime_dir(<out_dir>)``
#
# Returns the normalized scratch directory. ``CDPM_RUNTIME_DIR`` overrides the library default
# ``${CMAKE_BINARY_DIR}/.cdpm``; a relative override is interpreted from ``CMAKE_BINARY_DIR``.
function(_cdpm_resolve_runtime_dir out_dir)
    if(DEFINED CDPM_RUNTIME_DIR AND NOT CDPM_RUNTIME_DIR STREQUAL "")
        set(dir "${CDPM_RUNTIME_DIR}")
    else()
        set(dir "${CMAKE_BINARY_DIR}/.cdpm")
    endif()
    cmake_path(ABSOLUTE_PATH dir BASE_DIRECTORY "${CMAKE_BINARY_DIR}" NORMALIZE OUTPUT_VARIABLE dir)
    set(${out_dir} "${dir}")
    return(PROPAGATE ${out_dir})
endfunction()

# .. rst:
# ``_cdpm_resolve_cli_runtime_dir(<out_dir> <store_dir>)``
#
# Returns the CLI scratch directory. An explicit ``CDPM_RUNTIME_DIR`` wins. Otherwise the directory is
# project-scoped by the SHA-256 of the normalized project path and placed under the system temporary
# directory. ``<store_dir>/.runtime/<project-hash>`` is used only when no temporary directory is available.
function(_cdpm_resolve_cli_runtime_dir out_dir store_dir)
    if(DEFINED CDPM_RUNTIME_DIR AND NOT CDPM_RUNTIME_DIR STREQUAL "")
        _cdpm_resolve_runtime_dir(dir)
        set(${out_dir} "${dir}")
        return(PROPAGATE ${out_dir})
    endif()

    _cdpm_resolve_project_dir(project_dir)
    string(SHA256 project_hash "${project_dir}")

    set(temp_base "")
    foreach(env_var IN ITEMS TMPDIR TEMP TMP)
        if(DEFINED ENV{${env_var}} AND NOT "$ENV{${env_var}}" STREQUAL "")
            set(temp_base "$ENV{${env_var}}")
            break()
        endif()
    endforeach()

    if(NOT temp_base STREQUAL "")
        cmake_path(ABSOLUTE_PATH temp_base NORMALIZE OUTPUT_VARIABLE temp_base)
        set(dir "${temp_base}/cdpm/${project_hash}")
    else()
        set(dir "${store_dir}/.runtime/${project_hash}")
    endif()
    cmake_path(NORMAL_PATH dir OUTPUT_VARIABLE dir)

    set(${out_dir} "${dir}")
    return(PROPAGATE ${out_dir})
endfunction()

# .. rst:
# ``_cdpm_resolve_cache_dir(<out_dir>)``
#
# Returns the cdpm cache root used for reusable download artifacts. Precedence: a non-empty
# ``CDPM_CACHE_PATH`` (relative values normalized from ``CMAKE_BINARY_DIR``), then
# ``${CMAKE_BINARY_DIR}/.cdpm``. The directory is not created here - callers materialize the leaves they
# need.
function(_cdpm_resolve_cache_dir out_dir)
    if(DEFINED CDPM_CACHE_PATH AND NOT CDPM_CACHE_PATH STREQUAL "")
        set(dir "${CDPM_CACHE_PATH}")
    else()
        set(dir "${CMAKE_BINARY_DIR}/.cdpm")
    endif()
    cmake_path(ABSOLUTE_PATH dir BASE_DIRECTORY "${CMAKE_BINARY_DIR}" NORMALIZE OUTPUT_VARIABLE dir)
    set(${out_dir} "${dir}")
    return(PROPAGATE ${out_dir})
endfunction()

# .. rst:
# ``_cdpm_resolve_store_dir(<out_dir> [NO_CREATE])``
#
# Resolves the cdpm store directory with this precedence: the ``CDPM_STORE_DIR`` cache variable, then the
# merged config's ``store_dir`` (read from the ``CDPM_EFFECTIVE_CONFIG`` GLOBAL property; ignored when
# null/empty), then the platform default ``$ENV{HOME}/.cdpm/store`` (``$ENV{LOCALAPPDATA}/cdpm/store`` on
# Windows). The directory is created unless ``NO_CREATE`` is given. This reads the effective-config property
# directly and never includes ``cdpm_config`` - when config has not been loaded the platform default wins,
# preserving the standalone behaviour used by unit tests.
function(_cdpm_resolve_store_dir out_dir)
    cmake_parse_arguments(arg "NO_CREATE" "" "" ${ARGN})
    if(DEFINED CDPM_STORE_DIR AND NOT CDPM_STORE_DIR STREQUAL "")
        set(dir "${CDPM_STORE_DIR}")
    else()
        set(dir "")
        get_property(eff GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG)
        if(eff)
            string(JSON cfg_dir ERROR_VARIABLE dir_err GET "${eff}" "store_dir")
            if(NOT dir_err AND NOT cfg_dir STREQUAL "")
                set(dir "${cfg_dir}")
            endif()
        endif()
        if(dir STREQUAL "")
            if(CMAKE_HOST_WIN32 AND DEFINED ENV{LOCALAPPDATA})
                set(dir "$ENV{LOCALAPPDATA}/cdpm/store")
            else()
                set(dir "$ENV{HOME}/.cdpm/store")
            endif()
        endif()
    endif()

    if(NOT arg_NO_CREATE)
        file(MAKE_DIRECTORY "${dir}")
    endif()
    set(${out_dir} "${dir}")
    return(PROPAGATE ${out_dir})
endfunction()

# .. rst:
# ``_cdpm_install_slot_dir(<store_dir> <name> <config_hash> <out_dir>)``
#
# Returns the store slot ``<store>/<name>/<config-hash>`` for an installed package build. ``<name>`` is
# used verbatim (callers lower-case package names before storing). Owns the on-disk store layout so the
# convention has a single source of truth.
function(_cdpm_install_slot_dir store_dir name config_hash out_dir)
    set(${out_dir} "${store_dir}/${name}/${config_hash}")
    return(PROPAGATE ${out_dir})
endfunction()

# .. rst:
# ``_cdpm_build_slot_dir(<runtime_dir> <name> <config_hash> <out_dir>)``
#
# Returns the build scratch slot ``<runtime>/bs/<name>-<config-hash>`` used by the build drivers.
function(_cdpm_build_slot_dir runtime_dir name config_hash out_dir)
    set(${out_dir} "${runtime_dir}/bs/${name}-${config_hash}")
    return(PROPAGATE ${out_dir})
endfunction()

# =============================================================================
# Toolchain freeze constants (shared by generation, hashing and system probing)
# =============================================================================

# .. rst:
# ``__CDPM_TOOLCHAIN_VARS_BUILTIN``
#
# Built-in allow-list of toolchain variables that are *frozen* into the generated wrapper toolchain.
#
# Hunter forwards only ``CMAKE_TOOLCHAIN_FILE`` to child builds, which assumes every global setting lives
# in that file. That breaks when an IDE (e.g. Android Studio) injects the platform variables as ``-D``
# cache entries instead of via a toolchain file: the child build would not see them. cdpm therefore freezes
# a known set of variables - whichever are defined in the parent scope - into a wrapper toolchain that also
# ``include()``\s the real toolchain. Users extend the list via the ``CDPM_TOOLCHAIN_VARS`` cache variable.
set(__CDPM_TOOLCHAIN_VARS_BUILTIN
    # System identity
    CMAKE_SYSTEM_NAME CMAKE_SYSTEM_VERSION CMAKE_SYSTEM_PROCESSOR
    # Cross-compile roots
    CMAKE_SYSROOT CMAKE_FIND_ROOT_PATH
    CMAKE_FIND_ROOT_PATH_MODE_PACKAGE CMAKE_FIND_ROOT_PATH_MODE_PROGRAM
    CMAKE_FIND_ROOT_PATH_MODE_LIBRARY CMAKE_FIND_ROOT_PATH_MODE_INCLUDE
    # Build tooling / type / generator
    CMAKE_MAKE_PROGRAM CMAKE_BUILD_TYPE
    CMAKE_GENERATOR_PLATFORM CMAKE_GENERATOR_TOOLSET CMAKE_GENERATOR_INSTANCE
    # Android (NDK / Android Studio inject these as -D, not via a toolchain file)
    ANDROID_ABI ANDROID_PLATFORM CMAKE_ANDROID_ARCH_ABI CMAKE_ANDROID_NDK CMAKE_ANDROID_NDK
    ANDROID_STL ANDROID_ARM_NEON ANDROID_TOOLCHAIN
    # Apple
    CMAKE_OSX_ARCHITECTURES CMAKE_OSX_DEPLOYMENT_TARGET CMAKE_OSX_SYSROOT
    CACHE INTERNAL "cdpm built-in toolchain variable freeze allow-list" FORCE
)

# .. rst:
# ``__CDPM_TOOLCHAIN_SEMANTIC_NATIVE``
#
# Non-empty sentinel stamped into wrapper toolchains for native builds (no external toolchain).
# An empty marker value is deliberately not used: empty cache values are fragile as presence
# signals across contexts, while a fixed literal cannot collide with a real 16-hex semantic id.
set(__CDPM_TOOLCHAIN_SEMANTIC_NATIVE "native"
    CACHE INTERNAL "cdpm sentinel semantic id for native builds (no external toolchain)" FORCE
)

# .. rst:
# ``_cdpm_toolchain_var_list(<out_var>)``
#
# Returns the effective freeze allow-list: the built-in set (:cmake:variable:`__CDPM_TOOLCHAIN_VARS_BUILTIN`)
# unioned with the user-provided ``CDPM_TOOLCHAIN_VARS`` cache variable (duplicates removed, order stable).
# Shared by the wrapper generator, the config hash and system-dependency probing so they freeze/hash exactly
# the same variables.
function(_cdpm_toolchain_var_list out_var)
    set(vars ${__CDPM_TOOLCHAIN_VARS_BUILTIN})
    if(DEFINED CDPM_TOOLCHAIN_VARS)
        list(APPEND vars ${CDPM_TOOLCHAIN_VARS})
    endif()
    # Per-language compilers are always frozen (one entry per known language).
    foreach(lang IN ITEMS C CXX ASM ASM_NASM CUDA OBJC OBJCXX Fortran Swift)
        list(APPEND vars CMAKE_${lang}_COMPILER CMAKE_${lang}_COMPILER_AR CMAKE_${lang}_COMPILER_RANLIB)
    endforeach()
    list(REMOVE_DUPLICATES vars)
    set(${out_var} "${vars}")
    return(PROPAGATE ${out_var})
endfunction()

# =============================================================================
# Small cross-module primitives
# =============================================================================

# .. rst:
# ``_cdpm_get_host_processor(<out_var>)``
#
# Returns the host processor name. Works in both project mode (reads
# ``CMAKE_HOST_SYSTEM_PROCESSOR``) and script mode (falls back to
# ``cmake_host_system_information``).
function(_cdpm_get_host_processor out_var)
    if(DEFINED CMAKE_HOST_SYSTEM_PROCESSOR AND NOT CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "")
        set(${out_var} "${CMAKE_HOST_SYSTEM_PROCESSOR}")
        return(PROPAGATE ${out_var})
    endif()
    cmake_host_system_information(RESULT os_platform QUERY OS_PLATFORM)
    set(${out_var} "${os_platform}")
    return(PROPAGATE ${out_var})
endfunction()

# .. rst:
# ``_cdpm_expand_template(<template> <out_var> [<KEY> <value> ...])``
#
# Expands ``{<KEY>}`` placeholder tokens in ``<template>`` and stores the result in ``<out_var>``.
# Shared substitution path for URI shortcuts (``{path}``) and repo ``url_template`` (``{version}``)
# so there is a single ``string(REPLACE)`` implementation.
#
# Trailing arguments are consumed in ``KEY value`` pairs; each ``{KEY}`` literal is replaced by its ``value``.
# Keys are matched verbatim (case-sensitive).
function(_cdpm_expand_template template out_var)
    set(result "${template}")
    set(pairs ${ARGN})

    list(LENGTH pairs pairs_len)
    math(EXPR is_odd "${pairs_len} % 2")
    if(is_odd)
        message(FATAL_ERROR "[cdpm] _cdpm_expand_template: KEY/value arguments must come in pairs")
    endif()

    if(pairs_len GREATER 0)
        math(EXPR last_pair "${pairs_len} - 2")
        foreach(idx RANGE 0 ${last_pair} 2)
            math(EXPR val_idx "${idx} + 1")
            list(GET pairs ${idx} key)
            list(GET pairs ${val_idx} value)
            string(REPLACE "{${key}}" "${value}" result "${result}")
        endforeach()
    endif()

    set(${out_var} "${result}")
    return(PROPAGATE ${out_var})
endfunction()

# .. rst:
# ``_cdpm_kv_registry_set(<property_name> <key> <value> [OVERRIDE] [QUIET] [BUILTINS <list>])``
#
# Generic key-value registry stored as a flat list ``key;value;key;value;...`` in a GLOBAL property
# (never the cache, never global variables). Backs both the URI shortcut registry and the build-system driver registry.
#
# ``OVERRIDE``
#   Allow replacing an existing key. Without it, replacing an existing key is a fatal error
#   (downgraded to a warning + skip when ``QUIET`` is also given).
#
# ``QUIET``
#   With ``OVERRIDE``: replace silently. Without ``OVERRIDE``: turn the duplicate fatal error into a warning and skip registration.
#
# ``BUILTINS <list>``
#   Names considered built-in; overriding one emits a stronger trust warning.
#
# Security note: never pass ``OVERRIDE`` based on data read from a package repo
# or a dependency's CMakeLists.txt - that would allow supply-chain redirection.
function(_cdpm_kv_registry_set property_name key value)
    cmake_parse_arguments(arg "OVERRIDE;QUIET" "" "BUILTINS" ${ARGN})

    get_property(registry GLOBAL PROPERTY "${property_name}")
    list(FIND registry "${key}" key_idx)

    if(key_idx GREATER_EQUAL 0)
        if(NOT arg_OVERRIDE)
            if(arg_QUIET)
                message(WARNING "[cdpm] Registry '${property_name}': key '${key}' is already registered - skipping."
                    "Pass OVERRIDE to replace it."
                )
                return()
            else()
                message(FATAL_ERROR "[cdpm] Registry '${property_name}': key '${key}' is already registered."
                    "Pass OVERRIDE to replace it, or QUIET to skip silently."
                )
            endif()
        endif()

        # OVERRIDE: warn unless QUIET.
        if(NOT arg_QUIET)
            if(key IN_LIST arg_BUILTINS)
                message(WARNING "[cdpm] Overriding built-in registry entry '${key}' in '${property_name}'."
                    "Ensure the replacement is trusted."
                )
            else()
                message(WARNING "[cdpm] Overriding existing registry entry '${key}' in '${property_name}'.")
            endif()
        endif()

        math(EXPR value_idx "${key_idx} + 1")
        list(REMOVE_AT registry ${key_idx} ${value_idx})
    endif()

    list(APPEND registry "${key}" "${value}")
    set_property(GLOBAL PROPERTY "${property_name}" "${registry}")
endfunction()

# .. rst:
# ``_cdpm_kv_registry_get(<property_name> <key> <out_value> <out_found>)``
#
# Looks up ``<key>`` in a flat-list GLOBAL-property registry (see ``_cdpm_kv_registry_set``).
# Sets ``<out_found>`` to TRUE/FALSE and ``<out_value>`` to the stored value (empty when not found).
function(_cdpm_kv_registry_get property_name key out_value out_found)
    get_property(registry GLOBAL PROPERTY "${property_name}")
    list(FIND registry "${key}" key_idx)

    if(key_idx GREATER_EQUAL 0)
        math(EXPR value_idx "${key_idx} + 1")
        list(GET registry ${value_idx} value)
        set(${out_value} "${value}")
        set(${out_found} TRUE)
        return(PROPAGATE ${out_value} ${out_found})
    endif()

    set(${out_value} "")
    set(${out_found} FALSE)
    return(PROPAGATE ${out_value} ${out_found})
endfunction()
