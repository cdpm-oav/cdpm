# cdpm_hash.cmake - Deterministic build-configuration hashing for cdpm.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON iteration helpers (_cdpm_json_foreach / _cdpm_json_get) and the shared
# patch-applicability resolver (cdpm_resolve_patch_list).
include(cdpm_utils)
include(cdpm_verange)
include(cdpm_context)
include(cdpm_registry)

# .. rst:
# ``_cdpm_hash_compiler_part(<lang> <out_part>)``
#
# Builds the hash contribution for one enabled language ``<lang>``. The part combines the compiler
# identity (``CMAKE_<LANG>_COMPILER_ID``), its reported version (``CMAKE_<LANG>_COMPILER_VERSION``) and -
# when the compiler binary is reachable on disk - the SHA-256 of the binary itself
# (``file(SHA256 ${CMAKE_<LANG>_COMPILER})``). Hashing the binary, not just the version string, catches
# vendor rebuilds and local patches that keep the same advertised version but change code generation (the
# same approach vcpkg's ABI hash takes). When the binary is not reachable (cross builds, script mode where
# only the path string is known) the function degrades gracefully to id + version + path.
function(_cdpm_hash_compiler_part lang out_part)
    set(part "${lang}:${CMAKE_${lang}_COMPILER_ID}-${CMAKE_${lang}_COMPILER_VERSION}")

    set(compiler "${CMAKE_${lang}_COMPILER}")
    if(NOT compiler STREQUAL "")
        if(EXISTS "${compiler}" AND NOT IS_DIRECTORY "${compiler}")
            file(SHA256 "${compiler}" bin_hash)
            string(APPEND part "-bin:${bin_hash}")
        else()
            # Binary unreachable: fall back to the path string so a toolchain swap still moves the hash.
            string(APPEND part "-path:${compiler}")
        endif()
    endif()

    set(${out_part} "${part}")
    return(PROPAGATE ${out_part})
endfunction()

# .. rst:
# ``_cdpm_hash_languages_part(<out_part>)``
#
# Collects the per-language compiler contributions into a single deterministic string. The set of
# languages is taken from the global ``ENABLED_LANGUAGES`` property when a real project context exists
# (provider mode, inside ``project()``). In script mode (``cmake -P`` for the CLI) no languages are
# enabled, so the function falls back to whichever ``CMAKE_<LANG>_COMPILER`` variables are defined - these
# are normally populated from the prepared toolchain whose textual content is already folded into the hash
# separately. Languages are sorted so the order of detection never perturbs the hash.
function(_cdpm_hash_languages_part out_part)
    get_property(langs GLOBAL PROPERTY ENABLED_LANGUAGES)

    if(langs STREQUAL "")
        # Script-mode fallback: probe the common languages for a defined compiler variable.
        foreach(candidate IN ITEMS C CXX ASM ASM_NASM CUDA OBJC OBJCXX Fortran Swift)
            if(DEFINED CMAKE_${candidate}_COMPILER AND NOT CMAKE_${candidate}_COMPILER STREQUAL "")
                list(APPEND langs "${candidate}")
            endif()
        endforeach()
    endif()

    list(REMOVE_DUPLICATES langs)
    list(SORT langs)

    set(parts "")
    foreach(lang IN LISTS langs)
        _cdpm_hash_compiler_part("${lang}" lang_part)
        list(APPEND parts "${lang_part}")
    endforeach()

    list(JOIN parts "," joined)
    set(${out_part} "${joined}")
    return(PROPAGATE ${out_part})
endfunction()

# .. rst:
# ``_cdpm_hash_patches_part(<meta_json> <version> <out_part>)``
#
# Builds the hash contribution for the source patches that *apply to* ``<version>``. The applicable set and
# its order come from :cmake:command:`cdpm_resolve_patch_list` - the same resolver the build driver uses -
# so a patch that is scoped out of this version (via ``applies_to``/``exclude``) never perturbs its hash,
# and a version that does receive a patch is bound to that patch's content. Each applicable patch contributes
# only the SHA-256 of its content, so editing a patch forces a rebuild (mirroring Spack's per-patch sha256 and
# vcpkg's per-patch ABI entries) while keeping the hash independent of representation-specific paths. Relative
# paths use the schema-specific origin shared with the build path. No applicable patches yields an empty
# contribution. Apply order is preserved verbatim.
function(_cdpm_hash_patches_part pkg_name meta_json version out_part)
    set(result "")

    if(meta_json STREQUAL "" OR version STREQUAL "")
        set(${out_part} "")
        return(PROPAGATE ${out_part})
    endif()

    cdpm_resolve_patch_list("${meta_json}" "${version}" patches)

    string(JSON count LENGTH "${patches}")
    if(count EQUAL 0)
        set(${out_part} "")
        return(PROPAGATE ${out_part})
    endif()

    set(parts "")
    math(EXPR last "${count} - 1")
    foreach(i RANGE 0 ${last})
        string(JSON patch_path GET "${patches}" ${i})

        _cdpm_registry_resolve_patch_path("${pkg_name}" "${patch_path}" resolved)

        if(EXISTS "${resolved}" AND NOT IS_DIRECTORY "${resolved}")
            file(SHA256 "${resolved}" patch_hash)
            list(APPEND parts "${patch_hash}")
        else()
            # An unresolved patch still perturbs the hash deterministically.
            list(APPEND parts "missing")
        endif()
    endforeach()

    list(JOIN parts ";" joined)
    set(${out_part} "${joined}")
    return(PROPAGATE ${out_part})
endfunction()

# .. rst:
# ``cdpm_compute_config_hash(<pkg_name> <pkg_version> <meta_json> <out_hash>
#                           [DEPENDENCY_IDENTITIES <json>] [SYSTEM_IDENTITIES <json>])``
#
# Computes a deterministic 16-hex-character configuration hash that uniquely identifies a build of
# ``<pkg_name>`` at ``<pkg_version>`` under the current environment. Two builds that share this hash are
# considered binary-equivalent and reuse the same store slot.
#
# The hash is the leading 16 characters of the SHA-256 of a ``|``-separated component string:
#
# * ``<pkg>@<version>`` - identity;
# * per-language compiler identity, version and binary hash for every enabled language (see
#   :cmake:command:`_cdpm_hash_languages_part`);
# * ``CMAKE_VERSION`` - CMake injects implicit flags/macros that drift across releases, so the generator
#   tool version participates (as vcpkg's ABI hash does);
# * normalized absolute ``CMAKE_TOOLCHAIN_FILE`` path and SHA-256 of that root file's content when one is
#   set. The path is intentionally part of the identity because toolchains may use
#   ``CMAKE_CURRENT_LIST_DIR`` or relative includes. Transitive include contents are not recursively parsed;
#   the current contract tracks only the root toolchain identity;
# * ``CMAKE_SYSTEM_NAME``/``CMAKE_SYSTEM_PROCESSOR``, ``CMAKE_BUILD_TYPE``, ``CMAKE_GENERATOR``;
# * the package's canonical effective options (via ``cdpm_get_package_options`` when available) - for the
#   ``gn`` driver these are the native GN build args, for ``cmake`` the ``-D`` cache entries, etc.;
# * the package's tracked user key-values (via ``cdpm_get_package_user_kv``) - untracked entries
#   (secrets) are excluded by design;
# * the SHA-256 of every source patch applied to this version (see
#   :cmake:command:`_cdpm_hash_patches_part`);
# * ``CDPM_TOOLSET`` when defined;
# * platform-specific adders: Android (``ANDROID_ABI``/``ANDROID_PLATFORM``), Emscripten
#   (``EMSCRIPTEN_VERSION``), Apple embedded/macOS (``CMAKE_OSX_ARCHITECTURES``/
#   ``CMAKE_OSX_DEPLOYMENT_TARGET``).
#
# Dependencies on the configuration module (``cdpm_get_package_options`` / ``cdpm_get_package_user_kv``)
# are optional: when those commands are absent (pure hash unit tests) the corresponding components are
# omitted rather than failing.
function(cdpm_compute_config_hash pkg_name pkg_version meta_json out_hash)
    cmake_parse_arguments(arg "" "DEPENDENCY_IDENTITIES;SYSTEM_IDENTITIES" "" ${ARGN})
    if((DEFINED arg_DEPENDENCY_IDENTITIES OR DEFINED arg_SYSTEM_IDENTITIES) AND NOT COMMAND cdpm_canonical_json)
        include(cdpm_config)
    endif()
    string(TOLOWER "${pkg_name}" name)

    set(parts "${name}@${pkg_version}")

    # ---- Per-language compilers -------------------------------------------------
    _cdpm_hash_languages_part(lang_part)
    if(NOT lang_part STREQUAL "")
        string(APPEND parts "|lang:${lang_part}")
    endif()

    # ---- Build tool versions ----------------------------------------------------
    string(APPEND parts "|cmake:${CMAKE_VERSION}")

    # ---- Root toolchain identity ------------------------------------------------
    # The normalized path and root-file content are both required: byte-identical files at different paths
    # may behave differently through CMAKE_CURRENT_LIST_DIR or relative includes. Included files are not
    # recursively discovered or hashed.
    if(DEFINED CMAKE_TOOLCHAIN_FILE AND NOT CMAKE_TOOLCHAIN_FILE STREQUAL "")
        set(tc_path "${CMAKE_TOOLCHAIN_FILE}")
        cmake_path(ABSOLUTE_PATH tc_path BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" NORMALIZE OUTPUT_VARIABLE tc_path)
        if(EXISTS "${tc_path}")
            file(SHA256 "${tc_path}" tc_hash)
            string(APPEND parts "|tc:${tc_path}:${tc_hash}")
        endif()
    endif()

    # ---- Platform / generator / build type --------------------------------------
    string(APPEND parts
        "|sys:${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}"
        "|cfg:${CMAKE_BUILD_TYPE}"
        "|gen:${CMAKE_GENERATOR}")

    # ---- Effective package options ----------------------------------------------
    if(COMMAND cdpm_get_package_options)
        cdpm_get_package_options("${name}" "${pkg_version}" opts_json)
        string(APPEND parts "|opts:${opts_json}")
    endif()

    # ---- Tracked user key-values ------------------------------------------------
    if(COMMAND cdpm_get_package_user_kv)
        cdpm_get_package_user_kv("${name}" tracked_json untracked_json)
        string(APPEND parts "|user:${tracked_json}")
    endif()

    # ---- Source patches ---------------------------------------------------------
    _cdpm_hash_patches_part("${name}" "${meta_json}" "${pkg_version}" patches_part)
    if(NOT patches_part STREQUAL "")
        string(APPEND parts "|patches:${patches_part}")
    endif()

    if(DEFINED arg_SYSTEM_IDENTITIES)
        cdpm_canonical_json("${arg_SYSTEM_IDENTITIES}" system_identities)
        string(APPEND parts "|system:${system_identities}")
    endif()
    if(DEFINED arg_DEPENDENCY_IDENTITIES)
        cdpm_canonical_json("${arg_DEPENDENCY_IDENTITIES}" dependency_identities)
        string(APPEND parts "|dependencies:${dependency_identities}")
    endif()

    # ---- Optional toolset -------------------------------------------------------
    if(DEFINED CDPM_TOOLSET AND NOT CDPM_TOOLSET STREQUAL "")
        string(APPEND parts "|toolset:${CDPM_TOOLSET}")
    endif()

    # ---- Frozen toolchain variables ---------------------------------------------
    # The same allow-list that cdpm_prepare_toolchain freezes into the wrapper toolchain feeds the hash, so
    # an IDE-injected change (e.g. ANDROID_ABI, CMAKE_OSX_ARCHITECTURES) that is not part of any toolchain
    # file still moves the hash. Falls back to a minimal built-in set when cdpm_toolchain is not loaded.
    if(COMMAND _cdpm_toolchain_var_list)
        _cdpm_toolchain_var_list(tc_vars)
    else()
        set(tc_vars
            CMAKE_SYSTEM_NAME CMAKE_SYSTEM_VERSION CMAKE_SYSTEM_PROCESSOR
            ANDROID_ABI ANDROID_PLATFORM CMAKE_ANDROID_NDK ANDROID_STL
            CMAKE_OSX_ARCHITECTURES CMAKE_OSX_DEPLOYMENT_TARGET CMAKE_OSX_SYSROOT)
    endif()
    list(SORT tc_vars)
    set(tc_parts "")
    foreach(var IN LISTS tc_vars)
        if(DEFINED ${var} AND NOT "${${var}}" STREQUAL "")
            list(APPEND tc_parts "${var}=${${var}}")
        endif()
    endforeach()
    if(NOT tc_parts STREQUAL "")
        list(JOIN tc_parts ";" tc_joined)
        string(APPEND parts "|tcvars:${tc_joined}")
    endif()
    if(DEFINED EMSCRIPTEN_VERSION AND NOT EMSCRIPTEN_VERSION STREQUAL "")
        string(APPEND parts "|emsdk:${EMSCRIPTEN_VERSION}")
    endif()

    string(SHA256 full "${parts}")
    string(SUBSTRING "${full}" 0 16 short)
    set(${out_hash} "${short}")
    return(PROPAGATE ${out_hash})
endfunction()
