# cdpm_toolchain.cmake - Toolchain wrapper synthesis for isolated child builds.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

include(cdpm_context)

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
    # Build tooling / type
    CMAKE_MAKE_PROGRAM CMAKE_BUILD_TYPE
    # Android (NDK / Android Studio inject these as -D, not via a toolchain file)
    ANDROID_ABI ANDROID_PLATFORM CMAKE_ANDROID_ARCH_ABI ANDROID_NDK CMAKE_ANDROID_NDK
    ANDROID_STL ANDROID_ARM_NEON ANDROID_TOOLCHAIN
    # Apple
    CMAKE_OSX_ARCHITECTURES CMAKE_OSX_DEPLOYMENT_TARGET CMAKE_OSX_SYSROOT
    CACHE INTERNAL "cdpm built-in toolchain variable freeze allow-list"
)

# .. rst:
# ``_cdpm_toolchain_var_list(<out_var>)``
#
# Returns the effective freeze allow-list: the built-in set (:cmake:variable:`__CDPM_TOOLCHAIN_VARS_BUILTIN`)
# unioned with the user-provided ``CDPM_TOOLCHAIN_VARS`` cache variable (duplicates removed, order stable).
# Shared by the wrapper generator and the config hash so both freeze/hash exactly the same variables.
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

# .. rst:
# ``cdpm_prepare_toolchain(<config_hash> <out_toolchain_path> [HOST])``
#
# Generates (idempotently) the wrapper toolchain used to configure an isolated child build and returns its
# path in ``<out_toolchain_path>``. The wrapper lives at
# ``<runtime>/toolchain/<config_hash>.cmake`` (``-host.cmake`` in ``HOST`` mode).
#
# The wrapper:
#
# * ``include()``\s the real ``CMAKE_TOOLCHAIN_FILE`` first when one is set (so all of its logic still
#   applies - Hunter's "the toolchain file is the only global-settings channel", preserved);
# * then freezes every variable from the effective allow-list (see :cmake:command:`_cdpm_toolchain_var_list`)
#   that is defined and non-empty in the parent scope, with the parent's current value. This captures
#   IDE-injected ``-D`` variables (Android ``ANDROID_ABI`` etc.) that are not part of any toolchain file.
#
# Freezing after the ``include()`` makes the externally injected values win, matching what the parent build
# actually used. ``HOST`` mode is reserved for building build-time host tools natively when the target
# build cross-compiles; it currently emits the same wrapper under a distinct name. Emscripten targets
# require an external emsdk toolchain and are refused when none is set.
function(cdpm_prepare_toolchain config_hash out_toolchain_path)
    cmake_parse_arguments(arg "HOST" "" "" ${ARGN})

    set(external "")
    if(NOT arg_HOST AND DEFINED CMAKE_TOOLCHAIN_FILE AND NOT CMAKE_TOOLCHAIN_FILE STREQUAL "")
        if(NOT EXISTS "${CMAKE_TOOLCHAIN_FILE}")
            message(FATAL_ERROR "[cdpm] CMAKE_TOOLCHAIN_FILE does not exist: ${CMAKE_TOOLCHAIN_FILE}")
        endif()
        cmake_path(ABSOLUTE_PATH CMAKE_TOOLCHAIN_FILE NORMALIZE OUTPUT_VARIABLE external)
    elseif(NOT arg_HOST AND CMAKE_SYSTEM_NAME STREQUAL "Emscripten")
        message(FATAL_ERROR
            "[cdpm] Emscripten target requires an external emsdk toolchain; "
            "set CMAKE_TOOLCHAIN_FILE to emscripten/cmake/Modules/Platform/Emscripten.cmake."
        )
    endif()

    _cdpm_resolve_runtime_dir(runtime_dir)
    set(tc_dir "${runtime_dir}/toolchain")
    if(arg_HOST)
        set(tc_file "${tc_dir}/${config_hash}-host.cmake")
    else()
        set(tc_file "${tc_dir}/${config_hash}.cmake")
    endif()

    # Idempotent: the file name is hash-derived, so an existing wrapper is reused untouched.
    if(EXISTS "${tc_file}")
        set(${out_toolchain_path} "${tc_file}")
        return(PROPAGATE ${out_toolchain_path})
    endif()

    file(MAKE_DIRECTORY "${tc_dir}")

    set(lines "# Auto-generated by cdpm. Do not edit." "include_guard()")

    # Forward the real toolchain first so all of its logic applies.
    if(NOT external STREQUAL "")
        list(APPEND lines "include(\"${external}\")")
    endif()

    # Freeze the injected/effective values on top (IDE -D variables win, as the parent used them).
    if(arg_HOST)
        set(freeze_vars "")
    else()
        _cdpm_toolchain_var_list(freeze_vars)
    endif()
    foreach(var IN LISTS freeze_vars)
        if(DEFINED ${var} AND NOT "${${var}}" STREQUAL "")
            list(APPEND lines "set(${var} \"${${var}}\" CACHE STRING \"\" FORCE)")
        endif()
    endforeach()

    list(JOIN lines "\n" content)
    file(WRITE "${tc_file}" "${content}\n")

    set(${out_toolchain_path} "${tc_file}")
    return(PROPAGATE ${out_toolchain_path})
endfunction()
