# cdpm_hash.cmake - Deterministic build-configuration hashing for cdpm.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON iteration helpers (_cdpm_json_foreach / _cdpm_json_get) and the shared
# patch-applicability resolver (cdpm_resolve_patch_list).
include(cdpm_utils)
include(cdpm_verange)
include(cdpm_context)
include(cdpm_registry)
include(cdpm_toolchain)

# .. rst:
# ``_cdpm_hash_compiler_part(<lang> <out_part>)``
#
# Builds the hash contribution for one enabled language ``<lang>``. The authoritative identity is the
# compiler binary itself: when the binary is reachable on disk we hash it with SHA-256. This catches
# vendor rebuilds and local patches that keep the same advertised version but change code generation (the
# same approach vcpkg's ABI hash takes), and it makes the hash independent of whether the language was
# only probed with :cmake:command:`check_language` or fully enabled by ``project()`` / ``enable_language``.
# When the binary is not reachable (cross builds, script mode where only the path string is known) the
# function degrades gracefully to id + version + path.
function(_cdpm_hash_compiler_part lang out_part)
    set(compiler "${CMAKE_${lang}_COMPILER}")
    if(compiler STREQUAL "")
        set(part "${lang}:none")
    elseif(EXISTS "${compiler}" AND NOT IS_DIRECTORY "${compiler}")
        # Binary reachable: use its content hash as the authoritative identity.
        file(SHA256 "${compiler}" bin_hash)
        set(part "${lang}:bin:${bin_hash}")
    else()
        # Binary unreachable: fall back to the declared id/version/path so a toolchain
        # swap still moves the hash.
        set(part "${lang}:${CMAKE_${lang}_COMPILER_ID}-${CMAKE_${lang}_COMPILER_VERSION}-path:${compiler}")
    endif()

    set(${out_part} "${part}")
    return(PROPAGATE ${out_part})
endfunction()

# .. rst:
# ``_cdpm_hash_languages_part(<out_part>)``
#
# Collects the per-language compiler contributions into a single deterministic string. The canonical
# language set comes from the defined ``CMAKE_<LANG>_COMPILER`` variables for the known language list;
# this is independent of which languages the current project happened to ``enable_language()`` so the hash
# converges between CLI script mode, the orchestrator project and nested provider-injected child builds.
# A compiler that reports ``-NOTFOUND`` (no working compiler for the language) is skipped so the hash
# stays clean on C-only hosts. Languages are sorted so the order of detection never perturbs the hash.
function(_cdpm_hash_languages_part out_part)
    set(langs "")
    foreach(candidate IN ITEMS C CXX ASM ASM_NASM CUDA OBJC OBJCXX Fortran Swift)
        if(DEFINED CMAKE_${candidate}_COMPILER)
            set(comp "${CMAKE_${candidate}_COMPILER}")
            if(NOT comp STREQUAL "" AND NOT comp MATCHES "-NOTFOUND$")
                list(APPEND langs "${candidate}")
            endif()
        endif()
    endforeach()

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
# * per-language compiler identity for every reachable compiler. The binary content is hashed when the
#   compiler is reachable on disk; otherwise the declared id/version/path are used (see
#   :cmake:command:`_cdpm_hash_languages_part`);
# * ``CMAKE_VERSION`` - CMake injects implicit flags/macros that drift across releases, so the generator
#   tool version participates (as vcpkg's ABI hash does);
# * the real toolchain's semantic identifier (path + content hash + frozen allow-list values, see
#   :cmake:command:`_cdpm_toolchain_semantic_id`). When running under a cdpm wrapper toolchain the wrapper
#   stamps ``CDPM_TOOLCHAIN_SEMANTIC_ID`` (a real 16-hex id, or the ``native`` sentinel for native builds)
#   and the hash uses that marker directly, ignoring the wrapper's volatile path and bytes; the sentinel
#   contributes no component at all, matching a top-level context without a toolchain. The path is
#   intentionally part of the identity because toolchains may use
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
    cmake_parse_arguments(arg "HOST" "DEPENDENCY_IDENTITIES;HOST_DEPENDENCY_IDENTITIES;SYSTEM_IDENTITIES" "" ${ARGN})
    if((DEFINED arg_DEPENDENCY_IDENTITIES OR DEFINED arg_HOST_DEPENDENCY_IDENTITIES
            OR DEFINED arg_SYSTEM_IDENTITIES) AND NOT COMMAND cdpm_canonical_json)
        include(cdpm_config)
    endif()
    string(TOLOWER "${pkg_name}" name)

    if(arg_HOST)
        set(parts "host:${name}@${pkg_version}")
    else()
        set(parts "target:${name}@${pkg_version}")
    endif()

    # ---- Per-language compilers -------------------------------------------------
    # HOST profile: host-only tools are identified by the host platform (OS + processor) plus, in a
    # NATIVE build only, the host C compiler. ``CMAKE_C_COMPILER`` is used because there is no standard
    # ``CMAKE_HOST_C_COMPILER`` variable; the orchestrator and nested provider builds canonicalize C
    # through :cmake:command:`check_language`, so the same binary is visible in every context and hash
    # convergence is guaranteed. Under cross-compilation ``CMAKE_C_COMPILER`` is the TARGET compiler,
    # while host tools are built natively (the HOST wrapper freezes nothing and includes no external
    # toolchain), so the compiler identity is deliberately excluded there: a cross consumer and the
    # matching cross orchestrator both see ``CMAKE_CROSSCOMPILING`` set and converge on the
    # platform-only slot instead of duplicating host tools per target toolchain. Host tools are not
    # compiled for a target triple, so the target toolchain, build type and generator never
    # participate. ``sys:<os>-<proc>`` remains the platform-only slot.
    if(arg_HOST)
        _cdpm_get_host_processor(host_proc)
        set(lang_part "host:${CMAKE_HOST_SYSTEM_NAME}-${host_proc}")
        if(NOT CMAKE_CROSSCOMPILING)
            set(host_compiler "${CMAKE_C_COMPILER}")
            if(DEFINED host_compiler AND NOT host_compiler STREQUAL ""
                    AND NOT host_compiler MATCHES "-NOTFOUND$")
                if(EXISTS "${host_compiler}" AND NOT IS_DIRECTORY "${host_compiler}")
                    file(SHA256 "${host_compiler}" host_bin_hash)
                    string(APPEND lang_part ":bin:${host_bin_hash}")
                else()
                    string(APPEND lang_part
                        ":${CMAKE_C_COMPILER_ID}-${CMAKE_C_COMPILER_VERSION}-path:${host_compiler}"
                    )
                endif()
            endif()
        endif()
    else()
        _cdpm_hash_languages_part(lang_part)
    endif()
    if(NOT lang_part STREQUAL "")
        string(APPEND parts "|lang:${lang_part}")
    endif()

    # ---- Build tool versions ----------------------------------------------------
    string(APPEND parts "|cmake:${CMAKE_VERSION}")

    # ---- Root toolchain identity ------------------------------------------------
    # Under a cdpm wrapper the wrapper itself must not move the hash; use the semantic marker stamped by
    # cdpm_prepare_toolchain. Current wrappers never stamp an empty marker: it is either a real 16-hex id
    # or the "native" sentinel. Both the sentinel and an empty value (wrappers from older cdpm versions)
    # denote a native build - the whole tc: component is absent, matching the top-level context where no
    # toolchain is in effect; this also holds when a context sees the sentinel without running under a
    # wrapper. A real id is written verbatim. Otherwise compute the semantic ID from the real
    # CMAKE_TOOLCHAIN_FILE so path and content still participate without binding to a generated wrapper.
    if(NOT arg_HOST)
        if(DEFINED CDPM_TOOLCHAIN_SEMANTIC_ID)
            if(NOT CDPM_TOOLCHAIN_SEMANTIC_ID STREQUAL ""
                    AND NOT CDPM_TOOLCHAIN_SEMANTIC_ID STREQUAL "${__CDPM_TOOLCHAIN_SEMANTIC_NATIVE}")
                string(APPEND parts "|tc:sem:${CDPM_TOOLCHAIN_SEMANTIC_ID}")
            endif()
        elseif(DEFINED CMAKE_TOOLCHAIN_FILE AND NOT CMAKE_TOOLCHAIN_FILE STREQUAL "")
            _cdpm_toolchain_var_list(tc_vars)
            _cdpm_toolchain_semantic_id("${CMAKE_TOOLCHAIN_FILE}" "${tc_vars}" sem_id)
            if(NOT sem_id STREQUAL "")
                string(APPEND parts "|tc:sem:${sem_id}")
            endif()
        endif()
    endif()

    # ---- Platform / generator / build type --------------------------------------
    if(arg_HOST)
        set(sys_name "${CMAKE_HOST_SYSTEM_NAME}")
        _cdpm_get_host_processor(sys_proc)
    else()
        set(sys_name "${CMAKE_SYSTEM_NAME}")
    endif()
    if(NOT DEFINED CMAKE_SYSTEM_NAME OR sys_name STREQUAL "")
        set(sys_name "${CMAKE_HOST_SYSTEM_NAME}")
    endif()
    if(NOT arg_HOST)
        set(sys_proc "${CMAKE_SYSTEM_PROCESSOR}")
    endif()
    if(sys_proc STREQUAL "")
        _cdpm_get_host_processor(sys_proc)
    endif()
    string(APPEND parts
        "|sys:${sys_name}-${sys_proc}"
    )
    if(NOT arg_HOST)
        string(APPEND parts
            "|cfg:${CMAKE_BUILD_TYPE}"
            "|gen:${CMAKE_GENERATOR}"
        )
    endif()

    # ---- Effective package options ----------------------------------------------
    if(COMMAND cdpm_get_package_options)
        cdpm_get_package_options("${name}" "${pkg_version}" opts_json)
        string(APPEND parts "|opts:${opts_json}")
    endif()

    # ---- Build-system override --------------------------------------------------
    # A user-configured packages.<pkg>.build_system override changes the driver that
    # runs the build, so it must move the binary identity.
    if(COMMAND cdpm_get_package_build_system_override)
        cdpm_get_package_build_system_override("${name}" bs_override bs_override_found)
        if(bs_override_found AND NOT bs_override STREQUAL "")
            string(APPEND parts "|bs:${bs_override}")
        endif()
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
    if(DEFINED arg_HOST_DEPENDENCY_IDENTITIES)
        cdpm_canonical_json("${arg_HOST_DEPENDENCY_IDENTITIES}" host_dependency_identities)
        string(APPEND parts "|host_dependencies:${host_dependency_identities}")
    endif()

    # ---- Optional toolset -------------------------------------------------------
    if(DEFINED CDPM_TOOLSET AND NOT CDPM_TOOLSET STREQUAL "")
        string(APPEND parts "|toolset:${CDPM_TOOLSET}")
    endif()

    # ---- Frozen toolchain variables ---------------------------------------------
    # The same allow-list that cdpm_prepare_toolchain freezes into the wrapper toolchain feeds the hash, so
    # an IDE-injected change (e.g. ANDROID_ABI, CMAKE_OSX_ARCHITECTURES) that is not part of any toolchain
    # file still moves the hash. Falls back to a minimal built-in set when cdpm_toolchain is not loaded.
    if(arg_HOST)
        set(tc_vars "")
    elseif(COMMAND _cdpm_toolchain_var_list)
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
