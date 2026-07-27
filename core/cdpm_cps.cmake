# cdpm_cps.cmake - Common Package Specification descriptor generation for cdpm.
#
# Emits ``cps_version`` 0.14.1 -- the CPS revision implemented by CMake 4.3 (its find_package CPS reader
# rejects a newer minor such as 0.15.0 with "package description file could not be read"). The field
# semantics used here are stable across CPS 0.13-0.15; only the declared version is pinned to what the
# consuming tool understands.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# The CPS revision level implemented by CMake's find_package reader (4.3). Declaring a newer minor makes
# CMake refuse the file, so pin to the highest revision the target tool accepts.
set(__CDPM_CPS_VERSION "0.14.1" CACHE INTERNAL "CPS schema revision emitted by cdpm")

# JSON helpers (_cdpm_json_foreach / _cdpm_json_get), _cdpm_json_set_safe and cdpm_canonical_json.
include(cdpm_config)
# Host processor fallback for the platform.isa field in script mode.
include(cdpm_utils)

# .. rst:
# ``_cdpm_cps_find_library(<install_dir> <component> <out_location>)``
#
# Locates the installed library artifact for a compiled ``<component>`` under ``<install_dir>`` and returns
# a relocatable ``@prefix@/<relpath>`` location in ``<out_location>`` (empty when nothing matches).
#
# Searches ``lib`` then ``lib64`` for the conventional names of a static/shared library (``lib<c>.a``,
# ``lib<c>.so`` / ``lib<c>.so.*``, ``lib<c>.dylib``, ``<c>.lib``). Store slots hold exactly one build
# configuration, so the first match wins.
function(_cdpm_cps_find_library install_dir component out_location)
    set(${out_location} "")

    foreach(libdir IN ITEMS "lib" "lib64")
        set(base "${install_dir}/${libdir}")
        if(NOT IS_DIRECTORY "${base}")
            continue()
        endif()
        file(GLOB matches
            "${base}/lib${component}.a"
            "${base}/lib${component}.so"
            "${base}/lib${component}.so.*"
            "${base}/lib${component}.dylib"
            "${base}/${component}.lib"
        )
        if(matches)
            list(GET matches 0 hit)
            cmake_path(RELATIVE_PATH hit BASE_DIRECTORY "${install_dir}" OUTPUT_VARIABLE rel)
            set(${out_location} "@prefix@/${rel}")
            return(PROPAGATE ${out_location})
        endif()
    endforeach()

    return(PROPAGATE ${out_location})
endfunction()

# .. rst:
# ``_cdpm_cps_compose(<name> <version> <install_dir> <meta_json> <out_json>)``
#
# Builds a CPS ``package`` document (canonical JSON) from the registry metadata and the installed tree.
# ``<name>`` is lower-cased. Emits, when available:
#
# * ``cps_version`` / ``name`` / ``version`` / ``version_schema`` (default ``simple``);
# * ``cps_path`` = ``@prefix@/lib/cps`` (the tool derives ``@prefix@`` from the file's known location);
# * ``compat_version`` from ``meta.versions.<version>.compat_version``;
# * ``platform.kernel`` / ``platform.isa`` from ``CMAKE_SYSTEM_NAME`` / ``CMAKE_SYSTEM_PROCESSOR``
#   (each only when non-empty);
# * ``default_components`` (pruned to components actually emitted) and ``requires`` (from
#   ``meta.dependencies``, per-version override wins);
# * ``components``: ``interface`` components carry ``includes`` only; ``static`` / ``shared`` components also
#   get a discovered ``location`` (and ``link_languages: ["cpp"]`` for ``static``, so a consumer links the
#   C++ runtime). A compiled component whose library cannot be located is skipped with a warning (an invalid
#   location-less non-interface component is worse than an absent one).
function(_cdpm_cps_compose name version install_dir meta_json out_json)
    set(cps "{}")
    _cdpm_json_set_safe("${cps}" "cps_version" "${__CDPM_CPS_VERSION}" "STRING" cps)
    _cdpm_json_set_safe("${cps}" "name" "${name}" "STRING" cps)
    _cdpm_json_set_safe("${cps}" "version" "${version}" "STRING" cps)
    _cdpm_json_set_safe("${cps}" "cps_path" "@prefix@/lib/cps" "STRING" cps)

    # version_schema (default "simple").
    set(schema "simple")
    string(JSON schema_decl ERROR_VARIABLE e_schema GET "${meta_json}" "version_schema")
    if(NOT e_schema AND NOT schema_decl STREQUAL "")
        set(schema "${schema_decl}")
    endif()
    _cdpm_json_set_safe("${cps}" "version_schema" "${schema}" "STRING" cps)

    # compat_version from the resolved version's spec (optional).
    string(JSON compat ERROR_VARIABLE e_compat GET "${meta_json}" "versions" "${version}" "compat_version")
    if(NOT e_compat AND NOT compat STREQUAL "")
        _cdpm_json_set_safe("${cps}" "compat_version" "${compat}" "STRING" cps)
    endif()

    # platform.kernel / platform.isa. Guard with DEFINED first: in ``cmake -P`` script mode
    # CMAKE_SYSTEM_NAME/PROCESSOR are *undefined*, and ``if(NOT <undef> STREQUAL "")`` would treat the bare
    # name as a literal string (non-empty) and wrongly emit an empty value. Fall back to the host system
    # name and, via ``_cdpm_get_host_processor``, to the OS platform so the descriptor still records the
    # platform outside a configured build.
    set(sys_name "${CMAKE_SYSTEM_NAME}")
    if(NOT DEFINED CMAKE_SYSTEM_NAME OR sys_name STREQUAL "")
        set(sys_name "${CMAKE_HOST_SYSTEM_NAME}")
    endif()
    set(sys_proc "${CMAKE_SYSTEM_PROCESSOR}")
    if(NOT DEFINED CMAKE_SYSTEM_PROCESSOR OR sys_proc STREQUAL "")
        _cdpm_get_host_processor(sys_proc)
    endif()

    set(platform "{}")
    set(has_platform FALSE)
    if(NOT sys_name STREQUAL "")
        string(TOLOWER "${sys_name}" kernel)
        _cdpm_json_set_safe("${platform}" "kernel" "${kernel}" "STRING" platform)
        set(has_platform TRUE)
    endif()
    if(NOT sys_proc STREQUAL "")
        string(TOLOWER "${sys_proc}" isa)
        _cdpm_json_set_safe("${platform}" "isa" "${isa}" "STRING" platform)
        set(has_platform TRUE)
    endif()
    if(has_platform)
        string(JSON cps SET "${cps}" "platform" "${platform}")
    endif()

    # requires: package-level dependencies, overridden by the per-version dependencies when present.
    string(JSON deps ERROR_VARIABLE e_deps GET "${meta_json}" "dependencies")
    if(e_deps)
        set(deps "")
    endif()
    string(JSON ver_deps ERROR_VARIABLE e_vdeps GET "${meta_json}" "versions" "${version}" "dependencies")
    if(NOT e_vdeps AND NOT ver_deps STREQUAL "")
        set(deps "${ver_deps}")
    endif()
    if(NOT deps STREQUAL "")
        string(JSON cps SET "${cps}" "requires" "${deps}")
    endif()

    # components.
    set(components "{}")
    string(JSON comp_decl ERROR_VARIABLE e_comp GET "${meta_json}" "components")
    if(e_comp)
        set(comp_decl "{}")
    endif()

    set(has_include FALSE)
    if(IS_DIRECTORY "${install_dir}/include")
        set(has_include TRUE)
    endif()

    set(emitted_comps "")
    _cdpm_json_foreach("${comp_decl}" comp_keys)
    foreach(comp IN LISTS comp_keys)
        string(JSON comp_spec GET "${comp_decl}" "${comp}")

        set(ctype "interface")
        string(JSON ctype_decl ERROR_VARIABLE e_ctype GET "${comp_spec}" "type")
        if(NOT e_ctype AND NOT ctype_decl STREQUAL "")
            set(ctype "${ctype_decl}")
        endif()

        set(location "")
        if(ctype MATCHES [[(static|shared|module|executable)]])
            _cdpm_cps_find_library("${install_dir}" "${comp}" location)
            if(location STREQUAL "")
                message(WARNING "[cdpm] cps: component '${comp}' (type '${ctype}') of '${name}' has no "
                    "locatable library under lib/ or lib64/ -- skipping this component."
                )
                continue()
            endif()
        endif()

        set(cobj "{}")
        _cdpm_json_set_safe("${cobj}" "type" "${ctype}" "STRING" cobj)
        if(NOT location STREQUAL "")
            _cdpm_json_set_safe("${cobj}" "location" "${location}" "STRING" cobj)
        endif()
        # A CABI static library built from C++ requires the consumer to also link the C++ runtime; declare
        # it so consumers of any language get correct link behaviour (CPS default is ["c"]).
        if(ctype STREQUAL "static")
            string(JSON cobj SET "${cobj}" "link_languages" "[\"cpp\"]")
        endif()
        if(has_include)
            string(JSON cobj SET "${cobj}" "includes" "[\"@prefix@/include\"]")
        endif()

        string(JSON components SET "${components}" "${comp}" "${cobj}")
        list(APPEND emitted_comps "${comp}")
    endforeach()

    string(JSON cps SET "${cps}" "components" "${components}")

    # default_components, pruned to components that were actually emitted (a default that references a
    # skipped component would make the .cps unusable).
    string(JSON defcomp ERROR_VARIABLE e_defcomp GET "${meta_json}" "default_components")
    if(NOT e_defcomp AND NOT defcomp STREQUAL "")
        set(default_arr "[]")
        set(default_idx 0)
        string(JSON defcomp_len ERROR_VARIABLE e_dlen LENGTH "${defcomp}")
        if(NOT e_dlen AND defcomp_len GREATER 0)
            math(EXPR defcomp_last "${defcomp_len} - 1")
            foreach(i RANGE 0 ${defcomp_last})
                string(JSON dc GET "${defcomp}" ${i})
                # list(FIND) rather than if(... IN_LIST ...): the latter needs policy CMP0057 NEW, which is
                # not the default under the 3.25 baseline when this module is included from a bare script.
                list(FIND emitted_comps "${dc}" dc_idx)
                if(dc_idx GREATER_EQUAL 0)
                    _cdpm_json_set_safe("${default_arr}" ${default_idx} "${dc}" "STRING" default_arr)
                    math(EXPR default_idx "${default_idx} + 1")
                endif()
            endforeach()
        endif()
        if(default_idx GREATER 0)
            string(JSON cps SET "${cps}" "default_components" "${default_arr}")
        endif()
    endif()

    cdpm_canonical_json("${cps}" cps)
    set(${out_json} "${cps}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``cdpm_generate_cps_file(<pkg_name> <pkg_version> <install_dir> <meta_json>)``
#
# Post-install hook (invoked by :cmake:command:`cdpm_build_dependency`) that writes a CPS descriptor
# to ``<install_dir>/lib/cps/<name>.cps`` so ``find_package`` can consume the package via the Common Package
# Specification (native in CMake 4.3+). A ``.cps`` under ``lib/cps`` is what CMake's config-mode search
# actually looks for -- it only considers ``.cps`` files in directories whose path contains ``/cps/``.
#
# Opt-in: does nothing unless ``CDPM_GENERATE_CPS`` is truthy. Generation is intentionally off by default
# because a discovered ``.cps`` is *preferred* over a package's own ``*Config.cmake`` on CMake 4.3+.
function(cdpm_generate_cps_file pkg_name pkg_version install_dir meta_json)
    if(NOT CDPM_GENERATE_CPS)
        return()
    endif()

    string(TOLOWER "${pkg_name}" name)

    _cdpm_cps_compose("${name}" "${pkg_version}" "${install_dir}" "${meta_json}" cps_json)

    set(cps_dir "${install_dir}/lib/cps")
    file(MAKE_DIRECTORY "${cps_dir}")
    file(WRITE "${cps_dir}/${name}.cps" "${cps_json}\n")

    message(STATUS "[cdpm] cps: wrote ${cps_dir}/${name}.cps")
endfunction()
