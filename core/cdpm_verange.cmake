# cdpm_verange.cmake - Reusable version-range primitive for cdpm.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# JSON iteration helpers (_cdpm_json_foreach).
include(cdpm_utils)

# .. rst:
# ``cdpm_parse_version_range(<spec> <out_low> <out_high> <out_low_incl> <out_high_incl> <out_ok>)``
#
# Parses a version-range string into its components. This is the shared range grammar used across cdpm
# (patch applicability, default/option ranges, and - later - find_package constraints), so the syntax has a
# single implementation here.
#
# Accepted forms:
#
# * ``*``               - any version. Returns an unbounded inclusive range (``""`` .. ``""``).
# * ``<version>``       - a single version; a closed point range (``[v->v]``).
# * ``[a->b)`` etc.     - an explicit range. ``[`` / ``]`` mean an inclusive bound, ``(`` / ``)`` an
#                         exclusive bound. Either side may be empty for an open end: ``[a->)``, ``(->b]``,
#                         ``[->]``. The arrow separator is ``->``.
#
# On success ``<out_ok>`` is ``TRUE`` and the bounds are returned: ``<out_low>`` / ``<out_high>`` carry the
# bound versions (empty string = open end), ``<out_low_incl>`` / ``<out_high_incl>`` are ``TRUE``/``FALSE``
# for inclusivity. Any malformed input sets ``<out_ok>`` ``FALSE`` (the caller decides whether that is
# fatal); the bound outputs are then empty/FALSE.
function(cdpm_parse_version_range spec out_low out_high out_low_incl out_high_incl out_ok)
    set(${out_low} "")
    set(${out_high} "")
    set(${out_low_incl} FALSE)
    set(${out_high_incl} FALSE)
    set(${out_ok} FALSE)

    # Any version.
    if(spec STREQUAL "*")
        set(${out_low_incl} TRUE)
        set(${out_high_incl} TRUE)
        set(${out_ok} TRUE)
        return(PROPAGATE ${out_low} ${out_high} ${out_low_incl} ${out_high_incl} ${out_ok})
    endif()

    # Explicit bracketed range: <open>[low]-><high>]<close>.
    if(spec MATCHES "^([\\[(])(.*)->(.*)([])])$")
        set(open "${CMAKE_MATCH_1}")
        set(low "${CMAKE_MATCH_2}")
        set(high "${CMAKE_MATCH_3}")
        set(close "${CMAKE_MATCH_4}")

        if(open STREQUAL "[")
            set(low_incl TRUE)
        else()
            set(low_incl FALSE)
        endif()
        if(close STREQUAL "]")
            set(high_incl TRUE)
        else()
            set(high_incl FALSE)
        endif()

        # A non-empty bound must look like a version token.
        if(NOT low STREQUAL "" AND NOT low MATCHES "^[0-9][0-9.]*[0-9]$|^[0-9]+$")
            return(PROPAGATE ${out_low} ${out_high} ${out_low_incl} ${out_high_incl} ${out_ok})
        endif()
        if(NOT high STREQUAL "" AND NOT high MATCHES "^[0-9][0-9.]*[0-9]$|^[0-9]+$")
            return(PROPAGATE ${out_low} ${out_high} ${out_low_incl} ${out_high_incl} ${out_ok})
        endif()

        # An open end cannot be inclusive (there is no bound to include).
        if(low STREQUAL "" AND low_incl)
            return(PROPAGATE ${out_low} ${out_high} ${out_low_incl} ${out_high_incl} ${out_ok})
        endif()
        if(high STREQUAL "" AND high_incl)
            return(PROPAGATE ${out_low} ${out_high} ${out_low_incl} ${out_high_incl} ${out_ok})
        endif()

        set(${out_low} "${low}")
        set(${out_high} "${high}")
        set(${out_low_incl} "${low_incl}")
        set(${out_high_incl} "${high_incl}")
        set(${out_ok} TRUE)
        return(PROPAGATE ${out_low} ${out_high} ${out_low_incl} ${out_high_incl} ${out_ok})
    endif()

    # Single version -> closed point range [v->v].
    if(spec MATCHES "^[0-9][0-9.]*[0-9]$|^[0-9]+$")
        set(${out_low} "${spec}")
        set(${out_high} "${spec}")
        set(${out_low_incl} TRUE)
        set(${out_high_incl} TRUE)
        set(${out_ok} TRUE)
        return(PROPAGATE ${out_low} ${out_high} ${out_low_incl} ${out_high_incl} ${out_ok})
    endif()

    # Unrecognized.
    return(PROPAGATE ${out_low} ${out_high} ${out_low_incl} ${out_high_incl} ${out_ok})
endfunction()

# .. rst:
# ``_cdpm_require_exact_version(<pkg_name> <context> <spec> <out_ver>)``
#
# Validates that ``<spec>`` is a single exact version request, not a version range or malformed token.
# ``<context>`` is included in diagnostics (e.g. ``find_package`` or a registry dependency context).
# Empty ``<spec>`` yields an empty output. Legacy plain exact-looking tokens such as
# ``1.2.3-beta`` are accepted to preserve existing behavior.
function(_cdpm_require_exact_version pkg_name context spec out_ver)
    set(${out_ver} "")
    if(spec STREQUAL "")
        return(PROPAGATE ${out_ver})
    endif()

    # Reject any token that carries version-range syntax before parsing. This includes explicit
    # point ranges such as ``[1.2.3->1.2.3]``; only bare exact versions/pins are supported.
    if(spec MATCHES "[[]|[]]|[()]|[*]|->|[.][.][.]")
        message(FATAL_ERROR "[cdpm] package '${pkg_name}': version-range request '${spec}' "
            "(${context}) is not supported yet; exact requests/pins only.")
    endif()

    cdpm_parse_version_range("${spec}" low high low_incl high_incl ok)
    if(ok)
        if(NOT low STREQUAL "" AND low STREQUAL high AND low_incl AND high_incl)
            set(${out_ver} "${low}")
            return(PROPAGATE ${out_ver})
        endif()
        message(FATAL_ERROR "[cdpm] package '${pkg_name}': version-range request '${spec}' "
            "(${context}) is not supported yet; exact requests/pins only.")
    endif()

    # Accept plain exact-looking tokens (including pre-release/build-metadata suffixes) to keep
    # legacy behavior; treat everything else as an absent constraint.
    if(spec MATCHES "^[0-9]")
        set(${out_ver} "${spec}")
        return(PROPAGATE ${out_ver})
    endif()

    return(PROPAGATE ${out_ver})
endfunction()

# .. rst:
# ``cdpm_version_in_range(<version> <spec> <out_ok>)``
#
# Decides whether ``<version>`` falls inside the range string ``<spec>`` (parsed by
# :cmake:command:`cdpm_parse_version_range`). Comparisons use CMake's ``VERSION_*`` operators, so dotted
# numeric versions are ordered numerically (``10.0`` < ``10.2`` < ``11.0``). A malformed ``<spec>`` is
# fatal - a range that cannot be parsed is a registry authoring error, not a silent no-match.
#
# Bound semantics: an inclusive low bound passes ``version == low``; an exclusive low bound requires
# ``version > low``. Symmetrically for the high bound. An empty bound is treated as unbounded on that side.
function(cdpm_version_in_range version spec out_ok)
    set(${out_ok} FALSE)

    cdpm_parse_version_range("${spec}" low high low_incl high_incl ok)
    if(NOT ok)
        message(FATAL_ERROR "[cdpm] invalid version range '${spec}'.")
    endif()

    # Low bound.
    if(NOT low STREQUAL "")
        if(low_incl)
            if(version VERSION_LESS "${low}")
                return(PROPAGATE ${out_ok})
            endif()
        else()
            if(NOT version VERSION_GREATER "${low}")
                return(PROPAGATE ${out_ok})
            endif()
        endif()
    endif()

    # High bound.
    if(NOT high STREQUAL "")
        if(high_incl)
            if(version VERSION_GREATER "${high}")
                return(PROPAGATE ${out_ok})
            endif()
        else()
            if(NOT version VERSION_LESS "${high}")
                return(PROPAGATE ${out_ok})
            endif()
        endif()
    endif()

    set(${out_ok} TRUE)
    return(PROPAGATE ${out_ok})
endfunction()

# .. rst:
# ``cdpm_version_in_ranges(<version> <applies_to_json> <excludes_json> <out_ok>)``
#
# High-level applicability check combining the three authoring forms accepted across the registry into one
# yes/no answer. ``<version>`` is in scope when it matches *any* of the declared ranges (logical OR) and is
# *not* listed among the explicit exclusions ("holes" in an otherwise matching range).
#
# ``<applies_to_json>`` is the JSON value of an ``applies_to`` member and may be:
#
# * a JSON string  - a single range spec (``"[10.0->12.0)"``, ``"*"``, or a bare version);
# * a JSON array   - a list of exact versions (each element is treated as a single-version range);
# * a JSON object  - ``{ "from", "to", "from_include", "to_include" }``, normalized to a bracketed range;
# * the empty string / ``null`` - absent ``applies_to``: matches every version.
#
# ``<excludes_json>`` is an optional JSON array of exact version strings removed from the match (empty
# string / ``[]`` / null = none). A malformed range inside ``<applies_to_json>`` is fatal (authoring error).
function(cdpm_version_in_ranges version applies_to_json excludes_json out_ok)
    set(${out_ok} FALSE)

    # ---- Determine the match (OR over declared ranges) -------------------------
    set(matched FALSE)

    if(applies_to_json STREQUAL "" OR applies_to_json STREQUAL "null")
        # Absent applies_to: matches everything.
        set(matched TRUE)
    else()
        string(JSON at_type ERROR_VARIABLE at_err TYPE "${applies_to_json}")
        if(at_err)
            message(FATAL_ERROR "[cdpm] applies_to is not valid JSON: '${applies_to_json}'.")
        endif()

        if(at_type STREQUAL "STRING")
            string(JSON spec GET "${applies_to_json}")
            cdpm_version_in_range("${version}" "${spec}" matched)
        elseif(at_type STREQUAL "ARRAY")
            string(JSON count LENGTH "${applies_to_json}")
            if(count GREATER 0)
                math(EXPR last "${count} - 1")
                foreach(i RANGE 0 ${last})
                    string(JSON elem GET "${applies_to_json}" ${i})
                    cdpm_version_in_range("${version}" "${elem}" hit)
                    if(hit)
                        set(matched TRUE)
                        break()
                    endif()
                endforeach()
            endif()
        elseif(at_type STREQUAL "OBJECT")
            _cdpm_verange_object_to_spec("${applies_to_json}" spec)
            cdpm_version_in_range("${version}" "${spec}" matched)
        else()
            message(FATAL_ERROR "[cdpm] applies_to must be a string, array, or object (got ${at_type}).")
        endif()
    endif()

    if(NOT matched)
        return(PROPAGATE ${out_ok})
    endif()

    # ---- Apply exclusions ------------------------------------------------------
    if(NOT excludes_json STREQUAL "" AND NOT excludes_json STREQUAL "null")
        string(JSON ex_type ERROR_VARIABLE ex_err TYPE "${excludes_json}")
        if(NOT ex_err AND ex_type STREQUAL "ARRAY")
            string(JSON ex_count LENGTH "${excludes_json}")
            if(ex_count GREATER 0)
                math(EXPR ex_last "${ex_count} - 1")
                foreach(i RANGE 0 ${ex_last})
                    string(JSON ex_ver GET "${excludes_json}" ${i})
                    if(version VERSION_EQUAL "${ex_ver}")
                        # Excluded: a hole in the range.
                        return(PROPAGATE ${out_ok})
                    endif()
                endforeach()
            endif()
        endif()
    endif()

    set(${out_ok} TRUE)
    return(PROPAGATE ${out_ok})
endfunction()

# .. rst:
# ``cdpm_resolve_patch_list(<meta_json> <version> <out_paths_json>)``
#
# Builds the ordered list of patch file paths that apply to ``<version>`` and returns it as a JSON array of
# strings (paths exactly as authored in the registry; the caller resolves them to absolute paths). This is
# the single source of truth shared by the build driver (which applies the patches) and the config hash
# (which hashes their contents), so both always see the same set and order for a given version.
#
# Two declaration sites are merged, in this order:
#
# #. package-level ``<meta>.patches`` - an array of objects ``{ "file", "applies_to", "exclude" }``.
#    A patch is included when :cmake:command:`cdpm_version_in_ranges` says ``<version>`` is in scope
#    (absent ``applies_to`` means every version). Declaration order is preserved.
# #. per-version ``<meta>.versions.<version>.patches`` - the legacy array of bare path strings, all of
#    which apply to exactly this version. Appended after the package-level matches.
#
# A package-level entry missing ``file`` is fatal (authoring error). When neither site declares patches the
# result is ``[]``.
function(cdpm_resolve_patch_list meta_json version out_paths_json)
    set(result "[]")
    set(idx 0)

    if(meta_json STREQUAL "" OR version STREQUAL "")
        set(${out_paths_json} "${result}")
        return(PROPAGATE ${out_paths_json})
    endif()

    # ---- Package-level patches (object form, applicability-filtered) -----------
    string(JSON pkg_patches ERROR_VARIABLE pp_err GET "${meta_json}" "patches")
    if(NOT pp_err)
        string(JSON pp_type ERROR_VARIABLE ppt_err TYPE "${meta_json}" "patches")
        if(NOT ppt_err AND pp_type STREQUAL "ARRAY")
            string(JSON pp_count LENGTH "${pkg_patches}")
            if(pp_count GREATER 0)
                math(EXPR pp_last "${pp_count} - 1")
                foreach(i RANGE 0 ${pp_last})
                    string(JSON entry GET "${pkg_patches}" ${i})

                    string(JSON file ERROR_VARIABLE file_err GET "${entry}" "file")
                    if(file_err OR file STREQUAL "")
                        message(FATAL_ERROR "[cdpm] package patch entry #${i} is missing 'file'.")
                    endif()

                    # Rebuild a valid JSON value for applies_to: GET unwraps a string
                    # scalar (losing its quotes), so re-quote STRING members; ARRAY/OBJECT
                    # come back as valid JSON already.
                    string(JSON at_type ERROR_VARIABLE att_err TYPE "${entry}" "applies_to")
                    if(att_err)
                        set(applies "")
                    else()
                        string(JSON applies_raw GET "${entry}" "applies_to")
                        if(at_type STREQUAL "STRING")
                            set(applies "\"${applies_raw}\"")
                        else()
                            set(applies "${applies_raw}")
                        endif()
                    endif()

                    string(JSON excl ERROR_VARIABLE ex_err GET "${entry}" "exclude")
                    if(ex_err)
                        set(excl "")
                    endif()

                    cdpm_version_in_ranges("${version}" "${applies}" "${excl}" in_scope)
                    if(in_scope)
                        string(JSON result SET "${result}" ${idx} "\"${file}\"")
                        math(EXPR idx "${idx} + 1")
                    endif()
                endforeach()
            endif()
        endif()
    endif()

    # ---- Per-version patches (legacy array of path strings) --------------------
    string(JSON ver_patches ERROR_VARIABLE vp_err GET "${meta_json}" "versions" "${version}" "patches")
    if(NOT vp_err)
        string(JSON vp_type ERROR_VARIABLE vpt_err TYPE "${meta_json}" "versions" "${version}" "patches")
        if(NOT vpt_err AND vp_type STREQUAL "ARRAY")
            string(JSON vp_count LENGTH "${ver_patches}")
            if(vp_count GREATER 0)
                math(EXPR vp_last "${vp_count} - 1")
                foreach(i RANGE 0 ${vp_last})
                    string(JSON file GET "${ver_patches}" ${i})
                    string(JSON result SET "${result}" ${idx} "\"${file}\"")
                    math(EXPR idx "${idx} + 1")
                endforeach()
            endif()
        endif()
    endif()

    set(${out_paths_json} "${result}")
    return(PROPAGATE ${out_paths_json})
endfunction()

# .. rst:
# ``_cdpm_verange_object_to_spec(<obj_json> <out_spec>)``
#
# Converts the object form ``{ "from", "to", "from_include", "to_include" }`` into the canonical bracketed
# range string consumed by :cmake:command:`cdpm_parse_version_range`. Missing ``from``/``to`` become open
# ends; ``from_include`` defaults to ``true`` and ``to_include`` to ``false`` (the common half-open
# convention). The result is re-parsed by the caller, so an invalid combination still surfaces as a fatal
# range error there.
function(_cdpm_verange_object_to_spec obj_json out_spec)
    string(JSON from ERROR_VARIABLE f_err GET "${obj_json}" "from")
    if(f_err)
        set(from "")
    endif()
    string(JSON to ERROR_VARIABLE t_err GET "${obj_json}" "to")
    if(t_err)
        set(to "")
    endif()

    string(JSON from_incl ERROR_VARIABLE fi_err GET "${obj_json}" "from_include")
    if(fi_err)
        set(from_incl ON)
    endif()
    string(JSON to_incl ERROR_VARIABLE ti_err GET "${obj_json}" "to_include")
    if(ti_err)
        set(to_incl OFF)
    endif()

    # Open ends must use an exclusive bracket (an empty bound cannot be inclusive).
    if(from STREQUAL "")
        set(open "(")
    elseif(from_incl)
        set(open "[")
    else()
        set(open "(")
    endif()
    if(to STREQUAL "")
        set(close ")")
    elseif(to_incl)
        set(close "]")
    else()
        set(close ")")
    endif()

    set(${out_spec} "${open}${from}->${to}${close}")
    return(PROPAGATE ${out_spec})
endfunction()
