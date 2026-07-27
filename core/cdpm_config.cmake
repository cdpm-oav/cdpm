# cdpm_config.cmake - Configuration merging and canonicalization for cdpm.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)
# Modules carry no cmake_minimum_required, so set the policies they rely on explicitly to stay correct
# when included from a bare script under the 3.25 baseline:
#   CMP0057 -- if(... IN_LIST ...) operator;
#   CMP0007 -- list() commands do not silently drop empty elements (index math stays correct).
cmake_policy(SET CMP0057 NEW)
cmake_policy(SET CMP0007 NEW)

include(cdpm_utils) # JSON iteration helpers (_cdpm_json_foreach / _cdpm_json_get).
include(cdpm_uri) # URI parsing/validation (cdpm_parse_uri) - used by repo source validation.
include(cdpm_verange) # Version-range primitive (cdpm_parse_version_range) - used to validate patch/option ranges.
include(cdpm_context)
include(cdpm_registry)

# .. rst:
# ``_cdpm_json_set_safe(<json> <key> <value> <value_type> <out_json>)``
#
# Wrapper over ``string(JSON ... SET ...)`` that re-inserts a value previously obtained via
# ``string(JSON ... GET ...)`` while keeping it valid JSON.
#
# ``string(JSON ... GET ...)`` unwraps scalars: strings lose their quotes and booleans come back as
# ``ON``/``OFF`` on the 3.25 baseline. Feeding that raw text back into ``SET`` fails (a bare ``OFF`` or an
# unquoted string is not valid JSON), so this wrapper re-wraps by type: strings are JSON-quoted, booleans
# normalized to ``true``/``false``, objects/arrays/numbers/null inserted as-is.
function(_cdpm_json_set_safe json key value value_type out_json)
    if(value_type STREQUAL "STRING")
        # Re-quote and escape the string payload for embedding as a raw JSON token.
        string(REPLACE "\\" "\\\\" value "${value}")
        string(REPLACE "\"" "\\\"" value "${value}")
        set(json_value "\"${value}\"")
    elseif(value_type STREQUAL "BOOLEAN")
        if(value)
            set(json_value "true")
        else()
            set(json_value "false")
        endif()
    elseif(value_type STREQUAL "NULL")
        # GET returns an empty string for null; re-emit the JSON literal.
        set(json_value "null")
    else()
        # OBJECT / ARRAY / NUMBER are already valid JSON tokens.
        set(json_value "${value}")
    endif()
    string(JSON updated SET "${json}" "${key}" "${json_value}")
    set(${out_json} "${updated}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``_cdpm_split_key_operator(<raw_key> <out_key> <out_op>)``
#
# Splits a v1 merge operator suffix off a JSON object key.
#
# The ``!`` character is an operator only in the final position. A doubled trailing ``!!`` is an escape for
# a literal key ending in ``!`` (e.g. ``weird!!`` -> key ``weird!``, no operator). Sets ``<out_op>`` to
# ``REPLACE`` for ``key!`` and to the empty string otherwise; ``<out_key>`` always receives the resolved
# literal key (escapes collapsed).
function(_cdpm_split_key_operator raw_key out_key out_op)
    # Escaped literal: trailing "!!" -> literal single "!" suffix, no operator.
    if(raw_key MATCHES "!!$")
        string(REGEX REPLACE "!!$" "!" literal "${raw_key}")
        set(${out_key} "${literal}")
        set(${out_op} "")
        return(PROPAGATE ${out_key} ${out_op})
    endif()

    # Single trailing "!" -> REPLACE operator.
    if(raw_key MATCHES "^(.+)!$")
        set(${out_key} "${CMAKE_MATCH_1}")
        set(${out_op} "REPLACE")
        return(PROPAGATE ${out_key} ${out_op})
    endif()

    set(${out_key} "${raw_key}")
    set(${out_op} "")
    return(PROPAGATE ${out_key} ${out_op})
endfunction()

# .. rst:
# ``cdpm_merge_json(<base_json> <overlay_json> <out_json>)``
#
# Recursively merges ``overlay_json`` over ``base_json``.
#
# Default strategy: objects deep-merge; scalars and arrays are replaced by the overlay. The v1 key-suffix
# operator ``!`` forces full replacement of a key (``"key!": null`` removes the key, disabling deep merge).
# The merged result never contains operator keys - they are resolved here.
#
# When both sides expose a member as an object, the merge recurses; otherwise the overlay value wins. All
# JSON probes use ERROR_VARIABLE so missing members never abort configure (CMake >= 3.19).
function(cdpm_merge_json base_json overlay_json out_json)
    # Determine top-level types; only two objects can be deep-merged.
    string(JSON base_type ERROR_VARIABLE base_err TYPE "${base_json}")
    string(JSON overlay_type ERROR_VARIABLE overlay_err TYPE "${overlay_json}")

    # If overlay is not an object, or base is not an object, overlay replaces base.
    if(overlay_err OR NOT overlay_type STREQUAL "OBJECT"
            OR base_err OR NOT base_type STREQUAL "OBJECT")
        set(${out_json} "${overlay_json}")
        return(PROPAGATE ${out_json})
    endif()

    set(result "${base_json}")

    _cdpm_json_foreach("${overlay_json}" overlay_keys)
    foreach(raw_key IN LISTS overlay_keys)
        _cdpm_split_key_operator("${raw_key}" key op)
        _cdpm_json_get("${overlay_json}" "${raw_key}" overlay_value overlay_value_type)

        if(op STREQUAL "REPLACE")
            # Explicit replace/remove: never deep-merge this key.
            if(overlay_value_type STREQUAL "NULL")
                string(JSON result ERROR_VARIABLE rm_err REMOVE "${result}" "${key}")
                # Removing an absent key is not an error for us.
                if(rm_err)
                    # Key was absent in base - nothing to remove; keep result as-is.
                endif()
            else()
                _cdpm_json_set_safe("${result}" "${key}" "${overlay_value}"
                    "${overlay_value_type}" result)
            endif()
            continue()
        endif()

        # Default strategy: deep-merge only when both base and overlay members are objects.
        _cdpm_json_get("${result}" "${key}" base_value base_value_type)

        if(overlay_value_type STREQUAL "OBJECT" AND base_value_type STREQUAL "OBJECT")
            cdpm_merge_json("${base_value}" "${overlay_value}" merged_child)
            string(JSON result SET "${result}" "${key}" "${merged_child}")
        else()
            # Scalars and arrays: overlay replaces (booleans normalized to JSON literals).
            _cdpm_json_set_safe("${result}" "${key}" "${overlay_value}"
                "${overlay_value_type}" result)
        endif()
    endforeach()

    set(${out_json} "${result}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``cdpm_canonical_json(<json> <out_json>)``
#
# Produces a canonical form of ``json`` for stable hashing: object keys are sorted recursively and
# booleans are normalized to the literals ``true``/``false``.
#
# Rationale: on the CMake 3.25 baseline ``string(JSON ... GET ...)`` returns booleans as ``ON``/``OFF``, so
# a naive get-then-set round-trip could turn ``"x": true`` into ``"x": ON`` and change ``config_hash`` for
# an unchanged config. This function therefore re-emits booleans from their ``TYPE``, never from the raw
# ``GET`` text. Whitespace minimization is left to the caller's hash input (string(JSON SET) already yields
# compact, key-stable output).
function(cdpm_canonical_json json out_json)
    string(JSON value_type ERROR_VARIABLE type_err TYPE "${json}")

    if(type_err)
        # Not valid JSON we can introspect - pass through unchanged.
        set(${out_json} "${json}")
        return(PROPAGATE ${out_json})
    endif()

    if(value_type STREQUAL "OBJECT")
        _cdpm_json_foreach("${json}" keys)
        list(SORT keys)

        # Rebuild from an empty object so member order is deterministic.
        set(canonical "{}")
        foreach(key IN LISTS keys)
            _cdpm_json_get("${json}" "${key}" child child_type)
            if(child_type MATCHES [[^(OBJECT|ARRAY)$]])
                # Recurse to sort nested members; result is valid JSON, set directly.
                cdpm_canonical_json("${child}" child_canonical)
                string(JSON canonical SET "${canonical}" "${key}" "${child_canonical}")
            else()
                # Scalars: re-wrap by type (handles ON/OFF -> true/false, string quoting).
                _cdpm_json_set_safe("${canonical}" "${key}" "${child}" "${child_type}" canonical)
            endif()
        endforeach()
        set(${out_json} "${canonical}")
        return(PROPAGATE ${out_json})
    endif()

    if(value_type STREQUAL "ARRAY")
        # Arrays are order-significant - canonicalize elements, keep order.
        string(JSON arr_len ERROR_VARIABLE len_err LENGTH "${json}")
        set(canonical "[]")
        if(NOT len_err AND arr_len GREATER 0)
            math(EXPR arr_last "${arr_len} - 1")
            foreach(i RANGE 0 ${arr_last})
                string(JSON element_type ERROR_VARIABLE et_err TYPE "${json}" ${i})
                string(JSON element GET "${json}" ${i})
                if(element_type MATCHES [[^(OBJECT|ARRAY)$]])
                    cdpm_canonical_json("${element}" element_canonical)
                    string(JSON canonical SET "${canonical}" ${i} "${element_canonical}")
                else()
                    _cdpm_json_set_safe("${canonical}" ${i} "${element}" "${element_type}" canonical)
                endif()
            endforeach()
        endif()
        set(${out_json} "${canonical}")
        return(PROPAGATE ${out_json})
    endif()

    if(value_type STREQUAL "BOOLEAN")
        # Normalize ON/OFF (and any truthy form) back to JSON literals.
        if(json)
            set(${out_json} "true")
        else()
            set(${out_json} "false")
        endif()
        return(PROPAGATE ${out_json})
    endif()

    # STRING / NUMBER / NULL - emit as-is.
    set(${out_json} "${json}")
    return(PROPAGATE ${out_json})
endfunction()

# =============================================================================
# Config layer loading
# =============================================================================

# .. rst:
# ``_cdpm_builtin_defaults(<out_json>)``
#
# Layer 0: built-in defaults baked into cdpm. Returned as a JSON object so it merges through the same path
# as the on-disk layers.
function(_cdpm_builtin_defaults out_json)
    set(defaults [=[{
        "cdpm_schema": 1,
        "repos": [],
        "options": {},
        "packages": {},
        "user": {},
        "allow_system_packages": false,
        "allow_source_override": false,
        "store_dir": null
    }]=])
    set(${out_json} "${defaults}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``_cdpm_assert_no_integrity_overrides(<file> <packages_json>)``
#
# Enforcement for non-committed layers (cdpm_user.json, ~/.cdpm/config.json): a ``packages.<pkg>`` entry
# from such a layer may carry only local/dev knobs (``version``, ``options``, ``user``,
# ``source_override``). It must NOT carry integrity-sensitive fields - ``source``, ``url``, ``sha256``,
# ``rev``, ``versions``, ``patches``, ``build_script`` - those come solely from committed layers (repos and
# cdpm.json). Any such field raises ``FATAL_ERROR``. This closes the "a tool dropped a local config and
# silently swapped the source" scenario; legitimate local development goes through ``source_override``
# (local).
function(_cdpm_assert_no_integrity_overrides file packages_json)
    set(forbidden source url sha256 rev versions patches build_script)

    _cdpm_json_foreach("${packages_json}" pkg_keys)
    foreach(pkg IN LISTS pkg_keys)
        string(JSON pkg_obj GET "${packages_json}" "${pkg}")
        foreach(field IN LISTS forbidden)
            string(JSON probe ERROR_VARIABLE probe_err GET "${pkg_obj}" "${field}")
            if(NOT probe_err)
                message(FATAL_ERROR "[cdpm] Config layer '${file}' is not committed and may not set "
                    "integrity field 'packages.${pkg}.${field}'. Use source_override (local).")
            endif()
        endforeach()
    endforeach()
endfunction()

# .. rst:
# ``_cdpm_read_config_layer(<file> <committed> <out_json> <out_present>)``
#
# Reads and validates one config layer from ``<file>``.
#
# ``<committed>`` is TRUE for trusted/committed layers (cdpm.json, repos) and FALSE for local/machine
# layers (cdpm_user.json, ~/.cdpm/config.json). When FALSE, the layer must not carry integrity-sensitive
# fields - neither at the top level nor inside ``packages.<pkg>``
# (see :cmake:command:`_cdpm_assert_no_integrity_overrides`) - and may only override sources via
# ``source_override`` (local), validated later at source resolution.
#
# Sets ``<out_present>`` TRUE when the file exists and was parsed. A missing file is not an error (the layer
# is simply absent). Malformed JSON or an unknown ``cdpm_schema`` is a fatal error.
function(_cdpm_read_config_layer file committed out_json out_present)
    set(${out_json} "{}" PARENT_SCOPE)
    set(${out_present} FALSE PARENT_SCOPE)

    if(file STREQUAL "" OR NOT EXISTS "${file}")
        return()
    endif()

    file(READ "${file}" raw)

    # Validate it parses as a JSON object.
    string(JSON layer_type ERROR_VARIABLE type_err TYPE "${raw}")
    if(type_err OR NOT layer_type STREQUAL "OBJECT")
        message(FATAL_ERROR "[cdpm] Config layer '${file}' is not a JSON object: ${type_err}")
    endif()

    # Schema gate: accept only known versions (forward-compatible by major).
    string(JSON schema ERROR_VARIABLE schema_err GET "${raw}" "cdpm_schema")
    if(NOT schema_err AND NOT schema EQUAL 1)
        message(FATAL_ERROR "[cdpm] Config layer '${file}': unsupported cdpm_schema '${schema}' "
            "(this cdpm understands schema 1).")
    endif()

    # Integrity-sensitive fields are forbidden in non-committed layers, both at
    # the top level and per-package inside ``packages.<pkg>``.
    if(NOT committed)
        foreach(forbidden IN ITEMS "sha256" "rev" "patches" "build_script")
            string(JSON probe ERROR_VARIABLE probe_err GET "${raw}" "${forbidden}")
            if(NOT probe_err)
                message(FATAL_ERROR "[cdpm] Config layer '${file}' is not committed and may not "
                    "set integrity field '${forbidden}'. Use source_override (local) instead.")
            endif()
        endforeach()

        string(JSON packages ERROR_VARIABLE pkgs_err GET "${raw}" "packages")
        if(NOT pkgs_err)
            _cdpm_assert_no_integrity_overrides("${file}" "${packages}")
        endif()
    endif()

    set(${out_json} "${raw}" PARENT_SCOPE)
    set(${out_present} TRUE PARENT_SCOPE)
endfunction()

# .. rst:
# ``_cdpm_trace_layer(<label> <file> <json>)``
#
# Emits a STATUS line listing the top-level keys contributed by a layer when ``CDPM_CONFIG_TRACE`` is
# enabled (v1 diagnostics). Never logs values - only key names - so secrets in user KV are not exposed.
function(_cdpm_trace_layer label file json)
    if(NOT CDPM_CONFIG_TRACE)
        return()
    endif()
    _cdpm_json_foreach("${json}" keys)
    list(JOIN keys ", " key_list)
    message(STATUS "[cdpm] layer ${label} (${file}): keys = ${key_list}")
endfunction()

# .. rst:
# ``_cdpm_extract_repos(<layer_json> <inout_repos_var>)``
#
# Repos are concatenated by layer priority, not deep-merged: every layer's ``repos`` array is appended to a
# single ordered list, lower-priority layers first, so the first match wins later. The ``repos`` key is
# stripped from the object that goes into the deep-merge so it does not get array-replaced.
function(_cdpm_extract_repos layer_json inout_repos_var out_stripped_json)
    set(repos_acc "${${inout_repos_var}}")

    string(JSON repos_arr ERROR_VARIABLE repos_err GET "${layer_json}" "repos")
    if(NOT repos_err)
        string(JSON repos_type ERROR_VARIABLE rt_err TYPE "${layer_json}" "repos")
        if(NOT rt_err AND repos_type STREQUAL "ARRAY")
            string(JSON arr_len ERROR_VARIABLE len_err LENGTH "${repos_arr}")
            if(NOT len_err AND arr_len GREATER 0)
                math(EXPR arr_last "${arr_len} - 1")
                # Append into the accumulator array preserving order.
                string(JSON acc_len LENGTH "${repos_acc}")
                foreach(i RANGE 0 ${arr_last})
                    string(JSON entry GET "${repos_arr}" ${i})
                    math(EXPR dest "${acc_len} + ${i}")
                    string(JSON repos_acc SET "${repos_acc}" ${dest} "${entry}")
                endforeach()
            endif()
        endif()
    endif()

    # Strip repos from the layer so the object deep-merge ignores it.
    string(JSON stripped ERROR_VARIABLE strip_err REMOVE "${layer_json}" "repos")
    if(strip_err)
        set(stripped "${layer_json}")
    endif()

    set(${inout_repos_var} "${repos_acc}")
    set(${out_stripped_json} "${stripped}")
    return(PROPAGATE ${inout_repos_var} ${out_stripped_json})
endfunction()

# .. rst:
# ``_cdpm_record_origins(<layer_json> <label> <inout_origins_var>)``
#
# Records, for every dotted path a layer contributes, the layer ``<label>`` into a flat list
# ``path;label;path;label;...`` (the merge order means the last writer wins, matching effective
# precedence). This is the lightweight v1 backing for :cmake:command:`cdpm_config_blame`: paths are tracked
# at top-level granularity and one level deep for the container sections ``packages``/``user``/``options``
# (e.g. ``packages.fmt``), which covers the common "which layer set this package's knob" question without a
# shadow tree on the merge hot path.
function(_cdpm_record_origins layer_json label inout_origins_var)
    set(acc "${${inout_origins_var}}")

    _cdpm_json_foreach("${layer_json}" top_keys)
    foreach(raw_key IN LISTS top_keys)
        # Strip any merge operator suffix so the recorded path is the real key.
        _cdpm_split_key_operator("${raw_key}" key op)
        list(APPEND acc "${key}" "${label}")

        # Descend one level into the well-known container sections only.
        if(key MATCHES [[^(packages|user|options)$]])
            string(JSON sub_type ERROR_VARIABLE t_err TYPE "${layer_json}" "${raw_key}")
            if(NOT t_err AND sub_type STREQUAL "OBJECT")
                string(JSON sub GET "${layer_json}" "${raw_key}")
                _cdpm_json_foreach("${sub}" sub_keys)
                foreach(raw_sk IN LISTS sub_keys)
                    _cdpm_split_key_operator("${raw_sk}" sk sop)
                    list(APPEND acc "${key}.${sk}" "${label}")
                endforeach()
            endif()
        endif()
    endforeach()

    set(${inout_origins_var} "${acc}")
    return(PROPAGATE ${inout_origins_var})
endfunction()

# .. rst:
# ``cdpm_config_load([FORCE])``
#
# Loads and merges all config layers once per configure, caching the result in GLOBAL properties. Safe to
# call repeatedly: subsequent calls are no-ops unless ``FORCE`` is given (FORCE is primarily for tests).
#
# Layer order (low -> high priority): built-in defaults, ~/.cdpm/config.json (machine),
# <project>/cdpm.json (project), <project>/cdpm_user.json (project user). Objects deep-merge; ``repos``
# arrays concatenate by priority. CLI cache variables remain point overrides applied by callers on top of
# the result.
#
# Path overrides (cache variables; empty string disables the layer):
#   CDPM_MACHINE_CONFIG  default: $ENV{HOME}/.cdpm/config.json
#   CDPM_PROJECT_CONFIG  default: <project>/cdpm.json
#   CDPM_USER_CONFIG     default: <project>/cdpm_user.json
#
# Results (GLOBAL properties):
#   CDPM_CONFIG_LOADED     guard flag
#   CDPM_EFFECTIVE_CONFIG  merged object (operators resolved, repos stripped)
#   CDPM_REPO_JSON         {"repos": [...]} ordered by priority
#   CDPM_CONFIG_ORIGINS    flat path;label;... for cdpm_config_blame (v1)
function(cdpm_config_load)
    cmake_parse_arguments(arg "FORCE" "" "" ${ARGN})

    get_property(loaded GLOBAL PROPERTY CDPM_CONFIG_LOADED)
    if(loaded AND NOT arg_FORCE)
        return()
    endif()

    # Resolve layer paths (cache variables win; otherwise conventional defaults).
    _cdpm_resolve_project_dir(project_dir)
    if(NOT DEFINED CDPM_MACHINE_CONFIG)
        set(machine_config "$ENV{HOME}/.cdpm/config.json")
    else()
        set(machine_config "${CDPM_MACHINE_CONFIG}")
    endif()
    if(NOT DEFINED CDPM_PROJECT_CONFIG)
        set(project_config "${project_dir}/cdpm.json")
    else()
        set(project_config "${CDPM_PROJECT_CONFIG}")
    endif()
    if(NOT DEFINED CDPM_USER_CONFIG)
        set(user_config "${project_dir}/cdpm_user.json")
    else()
        set(user_config "${CDPM_USER_CONFIG}")
    endif()

    # Layer 0: built-in defaults.
    _cdpm_builtin_defaults(effective)
    set(repos_acc "[]")
    _cdpm_extract_repos("${effective}" repos_acc effective)
    _cdpm_trace_layer("0/defaults" "<builtin>" "${effective}")

    # Per-key origin tracking for cdpm_config_blame. A flat list
    # `path;label;path;label;...`; the last layer that contributes a path wins.
    set(origins "")
    _cdpm_record_origins("${effective}" "0/defaults" origins)

    # Layers 1..3. (label, file, committed?)
    foreach(spec
            "1/machine|${machine_config}|FALSE"
            "2/project|${project_config}|TRUE"
            "3/user|${user_config}|FALSE")
        string(REPLACE "|" ";" parts "${spec}")
        list(GET parts 0 label)
        list(GET parts 1 file)
        list(GET parts 2 committed)

        _cdpm_read_config_layer("${file}" "${committed}" layer_json present)
        if(NOT present)
            continue()
        endif()

        _cdpm_trace_layer("${label}" "${file}" "${layer_json}")
        _cdpm_extract_repos("${layer_json}" repos_acc layer_stripped)
        _cdpm_record_origins("${layer_stripped}" "${label}" origins)
        cdpm_merge_json("${effective}" "${layer_stripped}" effective)
    endforeach()

    # Post-merge diff trace: final top-level keys.
    if(CDPM_CONFIG_TRACE)
        _cdpm_json_foreach("${effective}" final_keys)
        list(JOIN final_keys ", " final_list)
        string(JSON repo_count LENGTH "${repos_acc}")
        message(STATUS "[cdpm] effective config keys = ${final_list}; repos = ${repo_count}")
    endif()

    string(JSON repo_json SET "{}" "repos" "${repos_acc}")

    set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "${effective}")
    set_property(GLOBAL PROPERTY CDPM_REPO_JSON "${repo_json}")
    set_property(GLOBAL PROPERTY CDPM_CONFIG_ORIGINS "${origins}")
    set_property(GLOBAL PROPERTY CDPM_CONFIG_LOADED TRUE)
    get_property(config_generation GLOBAL PROPERTY CDPM_CONFIG_GENERATION)
    if(NOT config_generation)
        set(config_generation 0)
    endif()
    math(EXPR config_generation "${config_generation} + 1")
    set_property(GLOBAL PROPERTY CDPM_CONFIG_GENERATION "${config_generation}")
    set_property(GLOBAL PROPERTY CDPM_PROVIDER_REPOS_LOADED FALSE)
endfunction()

# .. rst:
# ``cdpm_config_blame([PATH <dotted-path>] [OUTPUT <out_var>])``
#
# Reports the configuration layer that last set each tracked path, answering "which layer set this value".
# This is the pragmatic v1 form: origins are tracked at top-level granularity plus one level into
# ``packages``/``user``/``options`` (e.g. ``packages.fmt``), captured by
# :cmake:command:`_cdpm_record_origins` during :cmake:command:`cdpm_config_load`. A full recursive
# ``config blame`` (every leaf path) remains v2.
#
# With ``PATH`` only that path is reported; otherwise every recorded path is. Layer labels are
# ``0/defaults``, ``1/machine``, ``2/project``, ``3/user``. Without ``OUTPUT`` the result is printed via
# ``message(STATUS ...)``; with ``OUTPUT`` it is returned as a flat ``path;label;...`` list and not
# printed. Requires :cmake:command:`cdpm_config_load` to have run.
function(cdpm_config_blame)
    cmake_parse_arguments(arg "" "PATH;OUTPUT" "" ${ARGN})

    get_property(loaded GLOBAL PROPERTY CDPM_CONFIG_LOADED)
    if(NOT loaded)
        message(FATAL_ERROR "[cdpm] cdpm_config_blame: call cdpm_config_load() first.")
    endif()
    get_property(origins GLOBAL PROPERTY CDPM_CONFIG_ORIGINS)

    set(result "")
    if(DEFINED arg_PATH)
        # Last occurrence wins (matches effective precedence); scan front-to-back.
        set(found_label "")
        list(LENGTH origins n)
        if(n GREATER 0)
            math(EXPR pairs "${n} / 2 - 1")
            foreach(p RANGE 0 ${pairs})
                math(EXPR ki "${p} * 2")
                math(EXPR li "${ki} + 1")
                list(GET origins ${ki} k)
                if(k STREQUAL arg_PATH)
                    list(GET origins ${li} found_label)
                endif()
            endforeach()
        endif()
        if(found_label STREQUAL "")
            set(found_label "<unset>")
        endif()
        list(APPEND result "${arg_PATH}" "${found_label}")
    else()
        # Collapse to the last label per path, preserving first-seen order.
        set(seen_paths "")
        set(pairs -1)
        list(LENGTH origins n)
        if(n GREATER 0)
            math(EXPR pairs "${n} / 2 - 1")
            foreach(p RANGE 0 ${pairs})
                math(EXPR ki "${p} * 2")
                list(GET origins ${ki} k)
                if(NOT k IN_LIST seen_paths)
                    list(APPEND seen_paths "${k}")
                endif()
            endforeach()
        endif()
        foreach(k IN LISTS seen_paths)
            set(last_label "")
            foreach(p RANGE 0 ${pairs})
                math(EXPR ki "${p} * 2")
                math(EXPR li "${ki} + 1")
                list(GET origins ${ki} ck)
                if(ck STREQUAL k)
                    list(GET origins ${li} last_label)
                endif()
            endforeach()
            list(APPEND result "${k}" "${last_label}")
        endforeach()
    endif()

    if(DEFINED arg_OUTPUT)
        set(${arg_OUTPUT} "${result}")
        return(PROPAGATE ${arg_OUTPUT})
    endif()

    list(LENGTH result rn)
    if(rn EQUAL 0)
        message(STATUS "[cdpm] config blame: no recorded origins.")
        return()
    endif()
    math(EXPR rpairs "${rn} / 2 - 1")
    foreach(p RANGE 0 ${rpairs})
        math(EXPR ki "${p} * 2")
        math(EXPR li "${ki} + 1")
        list(GET result ${ki} k)
        list(GET result ${li} l)
        message(STATUS "[cdpm] blame ${k} <- ${l}")
    endforeach()
endfunction()

# =============================================================================
# Build-system driver registry
# =============================================================================

# Built-in driver names. Overriding one of these triggers a stronger
# trust warning via the _cdpm_kv_registry_* BUILTINS contract.
set(__cdpm_build_system_builtin_names
    cmake autotools make b2 openssl perl custom gn
    CACHE INTERNAL "cdpm built-in build-system driver names" FORCE
)

# Driver registry - flat list `name;module;name;module;...` in a GLOBAL property
# (not the cache, not global variables), exactly like __cdpm_uri_shortcut_registry.
set_property(GLOBAL PROPERTY __cdpm_build_systems "")

# Seed the built-in drivers (module paths are conventional: core/bs/cdpm_bs_<name>.cmake).
block(SCOPE_FOR VARIABLES)
    foreach(bs IN LISTS __cdpm_build_system_builtin_names)
        list(APPEND drivers "${bs}" "core/bs/cdpm_bs_${bs}.cmake")
    endforeach()
    set_property(GLOBAL PROPERTY __cdpm_build_systems "${drivers}")
endblock()

# .. rst:
# ``cdpm_register_build_system(<name> <module_path> [OVERRIDE] [QUIET])``
#
# Registers a build-system driver. A direct mirror of
# :cmake:command:`cdpm_register_uri_shortcut`: name is lower-cased, the entry is stored in the
# ``__cdpm_build_systems`` flat-list GLOBAL property via :cmake:command:`_cdpm_kv_registry_set`, and the
# OVERRIDE/QUIET/BUILTINS contract is identical. Without ``OVERRIDE``, replacing any existing driver is fatal
# (downgraded to a warning + skip with ``QUIET``); overriding a built-in driver warns more strongly.
#
# Security note: never pass ``OVERRIDE`` based on data read from a package repo - that would let a
# dependency redirect another package's build driver.
function(cdpm_register_build_system name module_path)
    cmake_parse_arguments(arg "OVERRIDE;QUIET" "" "" ${ARGN})

    if(module_path STREQUAL "")
        message(FATAL_ERROR "[cdpm] cdpm_register_build_system: module_path for '${name}' is empty.")
    endif()

    string(TOLOWER "${name}" name_key)

    set(forward "")
    if(arg_OVERRIDE)
        list(APPEND forward OVERRIDE)
    endif()
    if(arg_QUIET)
        list(APPEND forward QUIET)
    endif()

    _cdpm_kv_registry_set(__cdpm_build_systems "${name_key}" "${module_path}"
        ${forward} BUILTINS ${__cdpm_build_system_builtin_names})
endfunction()

# .. rst:
# ``cdpm_get_build_system(<name> <out_module> <out_found>)``
#
# Looks up a registered build-system driver by (lower-cased) name. Sets ``<out_found>`` TRUE/FALSE and
# ``<out_module>`` to the driver module path (empty when not found). Thin wrapper over
# :cmake:command:`_cdpm_kv_registry_get`.
function(cdpm_get_build_system name out_module out_found)
    string(TOLOWER "${name}" name_key)
    _cdpm_kv_registry_get(__cdpm_build_systems "${name_key}" module found)
    set(${out_module} "${module}")
    set(${out_found} "${found}")
    return(PROPAGATE ${out_module} ${out_found})
endfunction()

# =============================================================================
# Repository loading
# =============================================================================

# .. rst:
# ``_cdpm_validate_repo_source(<pkg_name> <pkg_json>)``
#
# Validates the ``source`` object of one package. The declared ``source.type``
# (git | url | local) is treated as intent and cross-checked against ``cdpm_parse_uri()``'s
# ``RESOURCE_TYPE`` (git<->GIT_REPO, url<->ARCHIVE, local<->LOCAL_PATH); a mismatch is fatal. ``@ref``
# embedded in ``source.url`` is forbidden (the version's ``rev``/``tag`` is the single source of truth).
# Any violation raises ``FATAL_ERROR``.
function(_cdpm_validate_repo_source pkg_name pkg_json)
    string(JSON src ERROR_VARIABLE src_err GET "${pkg_json}" "source")
    if(src_err)
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': missing required 'source' object.")
    endif()

    string(JSON src_type ERROR_VARIABLE type_err GET "${src}" "type")
    if(type_err)
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': source.type is required (git|url|local).")
    endif()

    # url for git/local, url_template for url-archives - exactly one applies.
    string(JSON url ERROR_VARIABLE url_err GET "${src}" "url")
    string(JSON url_tmpl ERROR_VARIABLE tmpl_err GET "${src}" "url_template")

    if(src_type STREQUAL "url")
        # Archive: url_template carries {version}; a bare url is also acceptable.
        if(tmpl_err AND url_err)
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': source.type=url requires "
                "'url' or 'url_template'.")
        endif()
        set(expected_resource "ARCHIVE")
        # url_template contains an unexpanded {version}; skip URI parsing of it.
        if(NOT url_err)
            set(probe_uri "${url}")
        else()
            set(probe_uri "")
        endif()
    elseif(src_type STREQUAL "git")
        if(url_err)
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': source.type=git requires 'url'.")
        endif()
        set(expected_resource "GIT_REPO")
        set(probe_uri "${url}")
    elseif(src_type STREQUAL "local")
        if(url_err)
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': source.type=local requires 'url'.")
        endif()
        set(expected_resource "LOCAL_PATH")
        set(probe_uri "${url}")
    else()
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': unknown source.type '${src_type}' "
            "(expected git|url|local).")
    endif()

    if(probe_uri STREQUAL "")
        return()
    endif()

    cdpm_parse_uri("${probe_uri}" PREFIX __repo_src)

    # @ref in a repo source URL is forbidden: the version's rev/tag is canonical.
    if(NOT __repo_src_REF STREQUAL "")
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': '@ref' is not allowed in source.url "
            "('${probe_uri}'); pin the version via versions.<v>.rev/tag instead.")
    endif()

    # Cross-check declared intent against the parsed resource type.
    if(NOT __repo_src_RESOURCE_TYPE STREQUAL "${expected_resource}")
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': source.type='${src_type}' but URL "
            "'${probe_uri}' parses as ${__repo_src_RESOURCE_TYPE} (expected ${expected_resource}).")
    endif()
endfunction()

# .. rst:
# ``_cdpm_validate_repo_patches(<pkg_name> <pkg_json>)``
#
# Validates the optional package-level ``patches`` array. Each entry must be an object carrying a non-empty
# ``file`` and, when present, an ``applies_to`` whose ranges parse via the version-range grammar (string,
# array of versions, or ``{from,to,...}`` object). A missing ``file`` or an unparseable range is fatal -
# the registry is committed metadata, so authoring errors should surface at load time, not at build time.
function(_cdpm_validate_repo_patches pkg_name pkg_json)
    string(JSON patches ERROR_VARIABLE p_err GET "${pkg_json}" "patches")
    if(p_err)
        return()
    endif()
    string(JSON p_type ERROR_VARIABLE pt_err TYPE "${pkg_json}" "patches")
    if(pt_err OR NOT p_type STREQUAL "ARRAY")
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': 'patches' must be an array of objects.")
    endif()

    string(JSON count LENGTH "${patches}")
    if(count EQUAL 0)
        return()
    endif()
    math(EXPR last "${count} - 1")
    foreach(i RANGE 0 ${last})
        string(JSON entry GET "${patches}" ${i})

        string(JSON file ERROR_VARIABLE f_err GET "${entry}" "file")
        if(f_err OR file STREQUAL "")
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': patches[${i}] is missing 'file'.")
        endif()

        # Validate any applies_to ranges by attempting a parse against a dummy version.
        string(JSON applies ERROR_VARIABLE at_err GET "${entry}" "applies_to")
        if(NOT at_err)
            string(JSON applies GET "${entry}" "applies_to")
            string(JSON at_type ERROR_VARIABLE att_err TYPE "${entry}" "applies_to")
            if(at_type STREQUAL "STRING")
                cdpm_parse_version_range("${applies}" lo hi li hii ok)
                if(NOT ok)
                    message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': patches[${i}] applies_to "
                        "'${applies}' is not a valid version range.")
                endif()
            elseif(at_type STREQUAL "ARRAY")
                string(JSON ac LENGTH "${applies}")
                if(ac GREATER 0)
                    math(EXPR al "${ac} - 1")
                    foreach(j RANGE 0 ${al})
                        string(JSON v GET "${applies}" ${j})
                        cdpm_parse_version_range("${v}" lo hi li hii ok)
                        if(NOT ok)
                            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': patches[${i}] "
                                "applies_to[${j}] '${v}' is not a valid version.")
                        endif()
                    endforeach()
                endif()
            elseif(NOT at_type STREQUAL "OBJECT")
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': patches[${i}] applies_to must "
                    "be a string, array, or object.")
            endif()
        endif()
    endforeach()
endfunction()

# .. rst:
# ``_cdpm_validate_repo_version_options(<pkg_name> <pkg_json>)``
#
# Validates the optional package-level ``version_options`` array: each entry must carry a ``range`` string
# that parses via the version-range grammar and an ``options`` object. These supply default build options
# to a span of versions (lower precedence than per-version ``options``). A bad range or a non-object
# ``options`` is fatal.
function(_cdpm_validate_repo_version_options pkg_name pkg_json)
    string(JSON vo ERROR_VARIABLE vo_err GET "${pkg_json}" "version_options")
    if(vo_err)
        return()
    endif()
    string(JSON vo_type ERROR_VARIABLE vot_err TYPE "${pkg_json}" "version_options")
    if(vot_err OR NOT vo_type STREQUAL "ARRAY")
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': 'version_options' must be an array.")
    endif()

    string(JSON count LENGTH "${vo}")
    if(count EQUAL 0)
        return()
    endif()
    math(EXPR last "${count} - 1")
    foreach(i RANGE 0 ${last})
        string(JSON entry GET "${vo}" ${i})

        string(JSON range ERROR_VARIABLE r_err GET "${entry}" "range")
        if(r_err OR range STREQUAL "")
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': version_options[${i}] is missing "
                "'range'.")
        endif()
        cdpm_parse_version_range("${range}" lo hi li hii ok)
        if(NOT ok)
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': version_options[${i}] range "
                "'${range}' is not a valid version range.")
        endif()

        string(JSON opts_type ERROR_VARIABLE ot_err TYPE "${entry}" "options")
        if(ot_err OR NOT opts_type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': version_options[${i}] requires an "
                "'options' object.")
        endif()
        string(JSON entry_opts GET "${entry}" options)
        _cdpm_validate_option_keys("${entry_opts}" "repo package '${pkg_name}' version_options[${i}]")
    endforeach()
endfunction()

# Validates keys that will become CMake cache variable names in a build driver.
function(_cdpm_validate_option_keys options context)
    string(JSON options_type ERROR_VARIABLE options_err TYPE "${options}")
    if(options_err OR NOT options_type STREQUAL "OBJECT")
        message(FATAL_ERROR "[cdpm] ${context}: options must be an object.")
    endif()
    _cdpm_json_foreach("${options}" option_keys)
    foreach(option_key IN LISTS option_keys)
        if(NOT option_key MATCHES [[^[A-Za-z_][A-Za-z0-9_]*$]])
            message(FATAL_ERROR "[cdpm] ${context}: option key '${option_key}' is not a safe CMake cache "
                "variable name.")
        endif()
    endforeach()
endfunction()

# .. rst:
# ``_cdpm_normalize_system_dependencies(<pkg_name> <json> <context> <out_json>)``
function(_cdpm_normalize_system_dependencies pkg_name json context out_json)
    string(JSON map_type ERROR_VARIABLE map_err TYPE "${json}")
    if(map_err OR NOT map_type STREQUAL "OBJECT")
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context} must be an object map.")
    endif()
    set(result "{}")
    string(JSON dependency_count LENGTH "${json}")
    if(dependency_count EQUAL 0)
        set(${out_json} "{}")
        return(PROPAGATE ${out_json})
    endif()
    math(EXPR dependency_last "${dependency_count} - 1")
    foreach(dependency_index RANGE 0 ${dependency_last})
        string(JSON dependency_name MEMBER "${json}" ${dependency_index})
        if(dependency_name STREQUAL "" OR NOT dependency_name MATCHES [[^[A-Za-z0-9_.+-]+$]])
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context} contains unsafe package name "
                "'${dependency_name}'.")
        endif()
        string(JSON spec_type TYPE "${json}" "${dependency_name}")
        if(NOT spec_type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name} must be an object.")
        endif()
        string(JSON spec GET "${json}" "${dependency_name}")
        _cdpm_json_foreach("${spec}" fields)
        foreach(field IN LISTS fields)
            if(NOT field MATCHES [[^(mode|version|components|identity_targets|identity_paths)$]])
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name} has unknown "
                    "field '${field}'.")
            endif()
        endforeach()

        string(JSON mode_type ERROR_VARIABLE mode_type_err TYPE "${spec}" mode)
        string(JSON mode ERROR_VARIABLE mode_err GET "${spec}" mode)
        if(mode_err OR mode_type_err OR NOT mode_type STREQUAL "STRING")
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}.mode must be "
                "CONFIG or MODULE.")
        endif()
        string(TOUPPER "${mode}" mode)
        if(NOT mode MATCHES [[^(CONFIG|MODULE)$]])
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}.mode must be "
                "CONFIG or MODULE.")
        endif()
        set(normalized "{}")
        _cdpm_json_set_safe("${normalized}" mode "${mode}" STRING normalized)

        string(JSON version ERROR_VARIABLE version_err GET "${spec}" version)
        if(NOT version_err)
            string(JSON version_type TYPE "${spec}" version)
            if(NOT version_type STREQUAL "STRING" OR version STREQUAL "")
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}.version must "
                    "be a non-empty string.")
            endif()
            _cdpm_json_set_safe("${normalized}" version "${version}" STRING normalized)
        endif()

        foreach(array_field IN ITEMS components identity_targets identity_paths)
            string(JSON array ERROR_VARIABLE array_err GET "${spec}" "${array_field}")
            if(array_err)
                if(array_field STREQUAL "identity_targets")
                    message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}."
                        "identity_targets is required.")
                endif()
                continue()
            endif()
            string(JSON array_type TYPE "${spec}" "${array_field}")
            if(NOT array_type STREQUAL "ARRAY")
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}."
                    "${array_field} must be an array of unique non-empty strings.")
            endif()
            string(JSON array_length LENGTH "${array}")
            if(array_field MATCHES [[^(identity_targets|identity_paths)$]] AND array_length EQUAL 0)
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}."
                    "${array_field} must not be empty.")
            endif()
            set(seen "")
            if(array_length GREATER 0)
                math(EXPR array_last "${array_length} - 1")
                foreach(i RANGE 0 ${array_last})
                    string(JSON item_type TYPE "${array}" ${i})
                    string(JSON item GET "${array}" ${i})
                    if(NOT item_type STREQUAL "STRING" OR item STREQUAL "" OR item IN_LIST seen)
                        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}."
                            "${array_field} must contain unique non-empty strings.")
                    endif()
                    if(array_field STREQUAL "identity_paths")
                        if(NOT item MATCHES [[^[A-Za-z0-9_.+@/~-]+$]]
                                OR item MATCHES [[(^/|^[A-Za-z]:|(^|/)\.\.(/|$))]])
                            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}."
                                "${dependency_name}.identity_paths must contain safe relative paths without '..'.")
                        endif()
                        cmake_path(NORMAL_PATH item OUTPUT_VARIABLE item)
                        if(item IN_LIST seen)
                            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}."
                                "${dependency_name}.identity_paths must be unique after normalization.")
                        endif()
                        _cdpm_json_set_safe("${array}" ${i} "${item}" STRING array)
                    endif()
                    list(APPEND seen "${item}")
                endforeach()
            endif()
            string(JSON normalized SET "${normalized}" "${array_field}" "${array}")
        endforeach()
        string(JSON result SET "${result}" "${dependency_name}" "${normalized}")
    endforeach()
    cdpm_canonical_json("${result}" result)
    set(${out_json} "${result}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``_cdpm_normalize_managed_dependencies(<pkg_name> <json> <context> <out_json>)``
function(_cdpm_normalize_managed_dependencies pkg_name json context out_json)
    string(JSON map_type ERROR_VARIABLE map_err TYPE "${json}")
    if(map_err OR NOT map_type STREQUAL "OBJECT")
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context} must be an object map.")
    endif()

    set(result "{}")
    _cdpm_json_foreach("${json}" dependency_names)
    foreach(dependency_name IN LISTS dependency_names)
        if(dependency_name STREQUAL "" OR NOT dependency_name MATCHES [[^[A-Za-z0-9_.+-]+$]])
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context} contains unsafe package name "
                "'${dependency_name}'.")
        endif()
        string(JSON spec_type TYPE "${json}" "${dependency_name}")
        if(NOT spec_type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name} must be an object.")
        endif()
        string(JSON spec GET "${json}" "${dependency_name}")
        _cdpm_json_foreach("${spec}" fields)
        foreach(field IN LISTS fields)
            if(NOT field MATCHES [[^(version|components)$]])
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name} has unknown "
                    "field '${field}'.")
            endif()
        endforeach()

        set(normalized "{}")
        string(JSON version ERROR_VARIABLE version_err GET "${spec}" version)
        if(NOT version_err)
            string(JSON version_type TYPE "${spec}" version)
            if(NOT version_type STREQUAL "STRING" OR version STREQUAL "")
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}.version must "
                    "be a non-empty string.")
            endif()
            _cdpm_json_set_safe("${normalized}" version "${version}" STRING normalized)
        endif()

        string(JSON components ERROR_VARIABLE components_err GET "${spec}" components)
        if(NOT components_err)
            string(JSON components_type TYPE "${spec}" components)
            if(NOT components_type STREQUAL "ARRAY")
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}.components "
                    "must be an array of unique non-empty strings.")
            endif()
            set(seen "")
            string(JSON component_count LENGTH "${components}")
            if(component_count GREATER 0)
                math(EXPR component_last "${component_count} - 1")
                foreach(i RANGE 0 ${component_last})
                    string(JSON component_type TYPE "${components}" ${i})
                    string(JSON component GET "${components}" ${i})
                    if(NOT component_type STREQUAL "STRING" OR component STREQUAL "" OR component IN_LIST seen)
                        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}."
                            "components must contain unique non-empty strings.")
                    endif()
                    list(APPEND seen "${component}")
                endforeach()
            endif()
            string(JSON normalized SET "${normalized}" components "${components}")
        endif()
        string(JSON result SET "${result}" "${dependency_name}" "${normalized}")
    endforeach()
    cdpm_canonical_json("${result}" result)
    set(${out_json} "${result}")
    return(PROPAGATE ${out_json})
endfunction()

# Normalizes build-time host dependencies. Host edges intentionally support only an exact, non-empty
# ``version`` request: components belong to target package consumption and are not meaningful for tools.
function(_cdpm_normalize_host_dependencies pkg_name json context out_json)
    cmake_policy(SET CMP0054 NEW)
    string(JSON map_type ERROR_VARIABLE map_err TYPE "${json}")
    if(map_err OR NOT map_type STREQUAL "OBJECT")
        message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context} must be an object map.")
    endif()
    set(result "{}")
    _cdpm_json_foreach("${json}" dependency_names)
    foreach(dependency_name IN LISTS dependency_names)
        if(dependency_name STREQUAL "" OR NOT dependency_name MATCHES [[^[A-Za-z0-9_.+-]+$]])
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context} contains unsafe package name "
                "'${dependency_name}'.")
        endif()
        string(JSON spec_type TYPE "${json}" "${dependency_name}")
        if(NOT spec_type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name} must be an object.")
        endif()
        string(JSON spec GET "${json}" "${dependency_name}")
        _cdpm_json_foreach("${spec}" fields)
        foreach(field IN LISTS fields)
            if(NOT field STREQUAL "version")
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name} has unknown "
                    "field '${field}'; host dependencies allow only 'version'.")
            endif()
        endforeach()
        string(JSON version ERROR_VARIABLE version_err GET "${spec}" version)
        string(JSON version_type ERROR_VARIABLE version_type_err TYPE "${spec}" version)
        if(version_err OR version_type_err OR NOT version_type STREQUAL "STRING" OR version STREQUAL "")
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': ${context}.${dependency_name}.version must be "
                "a non-empty string.")
        endif()
        set(normalized "{}")
        _cdpm_json_set_safe("${normalized}" version "${version}" STRING normalized)
        string(JSON result SET "${result}" "${dependency_name}" "${normalized}")
    endforeach()
    cdpm_canonical_json("${result}" result)
    set(${out_json} "${result}")
    return(PROPAGATE ${out_json})
endfunction()

function(_cdpm_assert_managed_dependency_sets_disjoint pkg_name target_json host_json context)
    _cdpm_json_foreach("${target_json}" target_names)
    _cdpm_json_foreach("${host_json}" host_names)
    foreach(target_name IN LISTS target_names)
        string(TOLOWER "${target_name}" target_key)
        foreach(host_name IN LISTS host_names)
            string(TOLOWER "${host_name}" host_key)
            if(target_key STREQUAL host_key)
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': dependency '${target_name}' appears in "
                    "both dependencies and host_dependencies (${context}).")
            endif()
        endforeach()
    endforeach()
endfunction()

# .. rst:
# ``_cdpm_assert_dependency_sets_disjoint(<pkg> <managed_json> <system_json> <context>)``
function(_cdpm_assert_dependency_sets_disjoint pkg_name managed_json system_json context)
    string(JSON managed_type ERROR_VARIABLE managed_err TYPE "${managed_json}")
    if(managed_err OR NOT managed_type STREQUAL "OBJECT")
        return()
    endif()
    _cdpm_json_foreach("${managed_json}" managed_names)
    _cdpm_json_foreach("${system_json}" system_names)
    foreach(managed_name IN LISTS managed_names)
        string(TOLOWER "${managed_name}" managed_key)
        foreach(system_name IN LISTS system_names)
            string(TOLOWER "${system_name}" system_key)
            if(managed_key STREQUAL system_key)
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': dependency '${managed_name}' appears in "
                    "both effective dependencies and system_dependencies (${context}).")
            endif()
        endforeach()
    endforeach()
endfunction()

# .. rst:
# ``_cdpm_validate_repo_system_dependencies(<pkg_name> <pkg_json>)``
function(_cdpm_validate_repo_system_dependencies pkg_name pkg_json)
    string(JSON package_system ERROR_VARIABLE package_system_err GET "${pkg_json}" system_dependencies)
    if(package_system_err)
        set(package_system "{}")
    else()
        _cdpm_normalize_system_dependencies("${pkg_name}" "${package_system}" system_dependencies package_system)
    endif()
    string(JSON package_managed ERROR_VARIABLE package_managed_err GET "${pkg_json}" dependencies)
    if(package_managed_err)
        set(package_managed "{}")
    endif()
    _cdpm_assert_dependency_sets_disjoint("${pkg_name}" "${package_managed}" "${package_system}" "package level")

    string(JSON versions ERROR_VARIABLE versions_err GET "${pkg_json}" versions)
    if(versions_err)
        return()
    endif()
    _cdpm_json_foreach("${versions}" version_names)
    foreach(version IN LISTS version_names)
        string(JSON effective_system ERROR_VARIABLE system_err GET
            "${versions}" "${version}" system_dependencies)
        if(system_err)
            set(effective_system "${package_system}")
        else()
            _cdpm_normalize_system_dependencies("${pkg_name}" "${effective_system}"
                "versions.${version}.system_dependencies" effective_system)
        endif()
        string(JSON effective_managed ERROR_VARIABLE managed_err GET "${versions}" "${version}" dependencies)
        if(managed_err)
            set(effective_managed "${package_managed}")
        endif()
        _cdpm_assert_dependency_sets_disjoint("${pkg_name}" "${effective_managed}" "${effective_system}"
            "version '${version}'")
    endforeach()
endfunction()

function(_cdpm_validate_repo_managed_dependencies pkg_name pkg_json)
    string(JSON package_dependencies ERROR_VARIABLE package_err GET "${pkg_json}" dependencies)
    if(package_err)
        set(package_dependencies "{}")
    else()
        _cdpm_normalize_managed_dependencies("${pkg_name}" "${package_dependencies}" dependencies
            package_dependencies)
    endif()
    string(JSON package_host ERROR_VARIABLE package_host_err GET "${pkg_json}" host_dependencies)
    if(package_host_err)
        set(package_host "{}")
    else()
        _cdpm_normalize_host_dependencies("${pkg_name}" "${package_host}" host_dependencies package_host)
    endif()
    _cdpm_assert_managed_dependency_sets_disjoint("${pkg_name}" "${package_dependencies}" "${package_host}"
        "package level")
    string(JSON versions ERROR_VARIABLE versions_err GET "${pkg_json}" versions)
    if(versions_err)
        return()
    endif()
    _cdpm_json_foreach("${versions}" version_names)
    foreach(version IN LISTS version_names)
        string(JSON version_dependencies ERROR_VARIABLE dependency_err GET
            "${versions}" "${version}" dependencies)
        if(NOT dependency_err)
            _cdpm_normalize_managed_dependencies("${pkg_name}" "${version_dependencies}"
                "versions.${version}.dependencies" unused)
        endif()
        if(dependency_err)
            set(effective_dependencies "${package_dependencies}")
        else()
            set(effective_dependencies "${version_dependencies}")
        endif()
        string(JSON version_host ERROR_VARIABLE host_err GET "${versions}" "${version}" host_dependencies)
        if(host_err)
            set(effective_host "${package_host}")
        else()
            _cdpm_normalize_host_dependencies("${pkg_name}" "${version_host}"
                "versions.${version}.host_dependencies" effective_host)
        endif()
        _cdpm_assert_managed_dependency_sets_disjoint("${pkg_name}" "${effective_dependencies}" "${effective_host}"
            "version '${version}'")
    endforeach()
endfunction()

# .. rst:
# ``_cdpm_validate_repo_package(<pkg_name> <pkg_json>)``
#
# Validates one package entry from a repository: a ``source`` object
# (via :cmake:command:`_cdpm_validate_repo_source`) and per-version integrity - ``source.type=url``
# requires ``sha256`` on every version, ``source.type=git`` requires a full ``rev``. Missing integrity data
# is a fatal error. When a ``build_system`` is declared it must name a registered driver. Optional
# package-level ``patches`` and ``version_options`` arrays are range-validated
# (:cmake:command:`_cdpm_validate_repo_patches` / :cmake:command:`_cdpm_validate_repo_version_options`).
function(_cdpm_validate_repo_package pkg_name pkg_json)
    _cdpm_validate_repo_source("${pkg_name}" "${pkg_json}")

    string(JSON package_options ERROR_VARIABLE package_options_err GET "${pkg_json}" options)
    if(NOT package_options_err)
        _cdpm_validate_option_keys("${package_options}" "repo package '${pkg_name}'")
    endif()

    # build_system (if present) must resolve to a registered driver.
    string(JSON bs ERROR_VARIABLE bs_err GET "${pkg_json}" "build_system")
    if(NOT bs_err)
        cdpm_get_build_system("${bs}" bs_module bs_found)
        if(NOT bs_found)
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': unknown build_system '${bs}' "
                "(no driver registered). Register one via cdpm_register_build_system().")
        endif()
    endif()

    # Package-level patches[] applicability ranges and version_options[] ranges
    # must parse - a malformed range is a registry authoring error, caught early.
    _cdpm_validate_repo_patches("${pkg_name}" "${pkg_json}")
    _cdpm_validate_repo_version_options("${pkg_name}" "${pkg_json}")
    _cdpm_validate_repo_managed_dependencies("${pkg_name}" "${pkg_json}")
    _cdpm_validate_repo_system_dependencies("${pkg_name}" "${pkg_json}")

    string(JSON find_name ERROR_VARIABLE find_name_err GET "${pkg_json}" find_package_name)
    if(NOT find_name_err)
        string(JSON find_name_type TYPE "${pkg_json}" find_package_name)
        if(NOT find_name_type STREQUAL "STRING" OR find_name STREQUAL "")
            message(FATAL_ERROR "[cdpm] repo package '${pkg_name}': find_package_name must be a non-empty string.")
        endif()
    endif()

    string(JSON src_type GET "${pkg_json}" "source" "type")

    string(JSON versions ERROR_VARIABLE ver_err GET "${pkg_json}" "versions")
    if(ver_err)
        # No versions block: nothing further to integrity-check here.
        return()
    endif()

    _cdpm_json_foreach("${versions}" version_keys)
    foreach(ver IN LISTS version_keys)
        string(JSON ver_obj GET "${versions}" "${ver}")
        if(src_type STREQUAL "git")
            string(JSON rev ERROR_VARIABLE rev_err GET "${ver_obj}" "rev")
            string(LENGTH "${rev}" rev_length)
            if(rev_err OR NOT rev_length EQUAL 40 OR NOT rev MATCHES [[^[0-9A-Fa-f]+$]])
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}' version '${ver}': git source "
                    "requires a full 'rev' (40-hex commit).")
            endif()
        elseif(src_type STREQUAL "url")
            string(JSON sha ERROR_VARIABLE sha_err GET "${ver_obj}" "sha256")
            string(LENGTH "${sha}" sha_length)
            if(sha_err OR NOT sha_length EQUAL 64 OR NOT sha MATCHES [[^[0-9A-Fa-f]+$]])
                message(FATAL_ERROR "[cdpm] repo package '${pkg_name}' version '${ver}': url source "
                    "requires 'sha256' as exactly 64 hex characters.")
            endif()
        endif()

        string(JSON version_options ERROR_VARIABLE version_options_err GET "${ver_obj}" options)
        if(NOT version_options_err)
            _cdpm_validate_option_keys("${version_options}" "repo package '${pkg_name}' version '${ver}'")
        endif()
    endforeach()
endfunction()

# .. rst:
# ``_cdpm_pkg_matches_masks(<name> <masks_json> <out_ok>)``
#
# Decides whether package ``<name>`` falls within a repository's ``packages`` ownership masks (vcpkg
# overlay-port model). ``<masks_json>`` is the JSON array of mask strings; an empty/absent array means
# "owns everything". A mask ending in ``*`` is a prefix mask, otherwise it is an exact name. The
# match precedence (exact > longest prefix) does not affect a single repo's yes/no decision, so
# ``<out_ok>`` is simply TRUE on any match.
function(_cdpm_pkg_matches_masks name masks_json out_ok)
    string(JSON masks_len ERROR_VARIABLE len_err LENGTH "${masks_json}")
    if(len_err OR masks_len EQUAL 0)
        # No masks declared: the repository owns every package.
        set(${out_ok} TRUE)
        return(PROPAGATE ${out_ok})
    endif()

    math(EXPR last "${masks_len} - 1")
    foreach(i RANGE 0 ${last})
        string(JSON mask GET "${masks_json}" ${i})
        string(TOLOWER "${mask}" mask)
        if(mask MATCHES "\\*$")
            string(LENGTH "${mask}" mask_len)
            math(EXPR prefix_len "${mask_len} - 1")
            string(SUBSTRING "${mask}" 0 ${prefix_len} prefix)
            string(LENGTH "${name}" name_len)
            if(name_len GREATER_EQUAL prefix_len)
                string(SUBSTRING "${name}" 0 ${prefix_len} name_prefix)
            else()
                set(name_prefix "")
            endif()
            if(name_prefix STREQUAL prefix)
                set(${out_ok} TRUE)
                return(PROPAGATE ${out_ok})
            endif()
        elseif(name STREQUAL mask)
            set(${out_ok} TRUE)
            return(PROPAGATE ${out_ok})
        endif()
    endforeach()

    set(${out_ok} FALSE)
    return(PROPAGATE ${out_ok})
endfunction()

# .. rst:
# ``cdpm_load_repo(<repo_file> [PACKAGES <masks_json>])``
#
# Loads, validates, and registers one package repository file (``packages.json``). Validation covers:
# ``version`` dispatch (version 1 manifest index), structural checks, per-package
# source/integrity rules, and ``@ref`` bans. Package keys are normalized to lower-case; a collision after
# normalization is a fatal error.
#
# ``PACKAGES`` is the optional JSON array of ownership masks from the ``repos[]`` entry
# (``["boost-*", "openssl"]``); only packages matching a mask are registered from this file
# (see :cmake:command:`_cdpm_pkg_matches_masks`). An absent/empty array registers every package.
#
# Manifest-index packages accumulate into the legacy ``CDPM_MERGED_REPO`` facade.
# Private lazy descriptors preserve first-registration-wins before manifests are read.
#
# This materializes a repository whose ``packages.json`` is already on disk (``kind: file`` directly, or
# ``kind: git`` after the baseline clone performed by :cmake:command:`cdpm_load_repos`).
function(cdpm_load_repo repo_file)
    cmake_parse_arguments(arg "" "PACKAGES" "" ${ARGN})
    if(DEFINED arg_PACKAGES)
        set(masks_json "${arg_PACKAGES}")
    else()
        set(masks_json "[]")
    endif()

    _cdpm_registry_load_repo("${repo_file}" "${masks_json}")
endfunction()

# .. rst:
# ``_cdpm_resolve_store_dir(<out_dir>)``
#
# Resolves the cdpm store directory with this precedence: the ``CDPM_STORE_DIR`` cache variable, then the
# merged config's ``store_dir`` (``CDPM_EFFECTIVE_CONFIG``; ignored when null/empty),
# then the platform default ``$ENV{HOME}/.cdpm/store`` (``$ENV{LOCALAPPDATA}/cdpm/store`` on Windows). The
# directory is created if missing.
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
# ``_cdpm_clone_repo_baseline(<url> <baseline> <out_repo_file>)``
#
# Materializes a ``kind: git`` repository at a pinned ``baseline`` (40-hex git SHA) inside the store,
# returning the path to its ``packages.json``. The checkout lives at ``<store>/repos/<baseline>``; an
# existing valid checkout is reused (the SHA makes the path content-addressed). After fetching, the
# resolved ``HEAD`` is verified to equal ``baseline`` - tags are mutable, so the pin is the single source
# of truth. Any git failure or HEAD mismatch is fatal. Requires ``Git`` on the host.
function(_cdpm_clone_repo_baseline url baseline out_repo_file)
    string(LENGTH "${baseline}" baseline_len)
    if(NOT baseline MATCHES "^[0-9a-fA-F]+$" OR NOT baseline_len EQUAL 40)
        message(FATAL_ERROR "[cdpm] git repo '${url}': baseline must be a full 40-hex commit SHA "
            "(got '${baseline}').")
    endif()

    find_program(GIT_EXECUTABLE NAMES git)
    if(NOT GIT_EXECUTABLE)
        message(FATAL_ERROR "[cdpm] git repo '${url}': Git was not found but is required to "
            "materialize a kind=git repository.")
    endif()

    _cdpm_resolve_store_dir(store)
    set(checkout "${store}/repos/${baseline}")
    set(repo_file "${checkout}/packages.json")

    # Content-addressed reuse: a present packages.json means a verified checkout.
    if(EXISTS "${repo_file}")
        set(${out_repo_file} "${repo_file}")
        return(PROPAGATE ${out_repo_file})
    endif()

    file(REMOVE_RECURSE "${checkout}")
    file(MAKE_DIRECTORY "${checkout}")

    # Fetch only the pinned commit (modern servers allow fetch-by-SHA).
    execute_process(COMMAND "${GIT_EXECUTABLE}" init --quiet "${checkout}"
        RESULT_VARIABLE rc ERROR_VARIABLE err
    )
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "[cdpm] git repo '${url}': git init failed: ${err}")
    endif()
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${checkout}" fetch --quiet --depth 1
            "${url}" "${baseline}"
        RESULT_VARIABLE rc ERROR_VARIABLE err
    )
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "[cdpm] git repo '${url}': fetch of baseline ${baseline} failed: ${err}")
    endif()
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${checkout}" checkout --quiet FETCH_HEAD
        RESULT_VARIABLE rc ERROR_VARIABLE err
    )
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "[cdpm] git repo '${url}': checkout of baseline failed: ${err}")
    endif()

    # Verify the resolved HEAD matches the requested pin.
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${checkout}" rev-parse HEAD
        OUTPUT_VARIABLE head OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE rc
    )
    string(TOLOWER "${head}" head)
    string(TOLOWER "${baseline}" want)
    if(NOT rc EQUAL 0 OR NOT head STREQUAL want)
        message(FATAL_ERROR "[cdpm] git repo '${url}': resolved HEAD '${head}' does not match "
            "baseline '${want}'.")
    endif()

    if(NOT EXISTS "${repo_file}")
        message(FATAL_ERROR "[cdpm] git repo '${url}' @ ${baseline}: no 'packages.json' at the "
            "repository root.")
    endif()

    set(${out_repo_file} "${repo_file}")
    return(PROPAGATE ${out_repo_file})
endfunction()

# .. rst:
# ``cdpm_load_repos()``
#
# Walks the priority-ordered ``repos`` list produced by :cmake:command:`cdpm_config_load`
# (``CDPM_REPO_JSON``) and registers each repository. The manifest-index reader eagerly validates the root index and
# records lazy manifest descriptors. Dispatch by
# ``kind``:
#
# * ``file`` - ``path`` resolved relative to the project directory when not absolute, loaded directly.
# * ``git`` - cloned at its ``baseline`` into the store (:cmake:command:`_cdpm_clone_repo_baseline`), then
#   loaded.
#
# Each repo's optional ``packages`` masks are forwarded to :cmake:command:`cdpm_load_repo`. Order in the
# array is the resolution priority (first registration wins); :cmake:command:`cdpm_config_load` must run
# first.
function(cdpm_load_repos)
    get_property(config_generation GLOBAL PROPERTY CDPM_CONFIG_GENERATION)
    get_property(loaded_generation GLOBAL PROPERTY CDPM_REGISTRY_CONFIG_GENERATION)
    if(NOT "${loaded_generation}" STREQUAL "${config_generation}")
        _cdpm_registry_reset()
        set_property(GLOBAL PROPERTY CDPM_REGISTRY_CONFIG_GENERATION "${config_generation}")
    endif()

    _cdpm_resolve_project_dir(project_dir)
    get_property(repo_json GLOBAL PROPERTY CDPM_REPO_JSON)
    if(NOT repo_json)
        return()
    endif()

    string(JSON repos ERROR_VARIABLE repos_err GET "${repo_json}" "repos")
    if(repos_err)
        return()
    endif()
    string(JSON repos_len ERROR_VARIABLE len_err LENGTH "${repos}")
    if(len_err OR repos_len EQUAL 0)
        return()
    endif()

    math(EXPR last "${repos_len} - 1")
    foreach(i RANGE 0 ${last})
        string(JSON entry GET "${repos}" ${i})

        string(JSON kind ERROR_VARIABLE kind_err GET "${entry}" "kind")
        if(kind_err)
            message(FATAL_ERROR "[cdpm] repos[${i}]: missing 'kind' (file|git).")
        endif()

        # Optional ownership masks (JSON array), forwarded to cdpm_load_repo.
        string(JSON masks ERROR_VARIABLE masks_err GET "${entry}" "packages")
        if(masks_err)
            set(masks "[]")
        endif()

        if(kind STREQUAL "file")
            string(JSON path ERROR_VARIABLE path_err GET "${entry}" "path")
            if(path_err)
                message(FATAL_ERROR "[cdpm] repos[${i}] (kind=file): missing 'path'.")
            endif()
            if(NOT IS_ABSOLUTE "${path}")
                cmake_path(ABSOLUTE_PATH path BASE_DIRECTORY "${project_dir}" NORMALIZE OUTPUT_VARIABLE path)
            endif()
            cdpm_load_repo("${path}" PACKAGES "${masks}")
        elseif(kind STREQUAL "git")
            string(JSON url ERROR_VARIABLE url_err GET "${entry}" "url")
            string(JSON baseline ERROR_VARIABLE bl_err GET "${entry}" "baseline")
            if(url_err)
                message(FATAL_ERROR "[cdpm] repos[${i}] (kind=git): missing 'url'.")
            endif()
            if(bl_err OR baseline STREQUAL "")
                message(FATAL_ERROR "[cdpm] repos[${i}] (kind=git): 'baseline' (40-hex SHA) is "
                    "required to pin the repository.")
            endif()
            _cdpm_clone_repo_baseline("${url}" "${baseline}" repo_file)
            cdpm_load_repo("${repo_file}" PACKAGES "${masks}")
        else()
            message(FATAL_ERROR "[cdpm] repos[${i}]: unknown kind '${kind}' (expected file|git).")
        endif()
    endforeach()
endfunction()

# =============================================================================
# Repository queries
# =============================================================================

function(cdpm_get_package_dependencies pkg_name meta_json version out_json)
    string(JSON dependencies ERROR_VARIABLE dependencies_err GET "${meta_json}" dependencies)
    if(dependencies_err)
        set(dependencies "{}")
    endif()
    if(NOT version STREQUAL "")
        string(JSON version_dependencies ERROR_VARIABLE version_err GET
            "${meta_json}" versions "${version}" dependencies)
        if(NOT version_err)
            set(dependencies "${version_dependencies}")
        endif()
    endif()
    _cdpm_normalize_managed_dependencies("${pkg_name}" "${dependencies}" "effective dependencies" result)
    set(${out_json} "${result}")
    return(PROPAGATE ${out_json})
endfunction()

# Returns the canonical host-tool map. A version-level declaration replaces the package-level map.
function(cdpm_get_package_host_dependencies pkg_name meta_json version out_json)
    string(JSON dependencies ERROR_VARIABLE dependencies_err GET "${meta_json}" host_dependencies)
    if(dependencies_err)
        set(dependencies "{}")
    endif()
    if(NOT version STREQUAL "")
        string(JSON version_dependencies ERROR_VARIABLE version_err GET
            "${meta_json}" versions "${version}" host_dependencies)
        if(NOT version_err)
            set(dependencies "${version_dependencies}")
        endif()
    endif()
    _cdpm_normalize_host_dependencies("${pkg_name}" "${dependencies}" "effective host_dependencies" result)
    set(${out_json} "${result}")
    return(PROPAGATE ${out_json})
endfunction()

function(cdpm_get_package_find_name pkg_key meta_json out_name)
    string(JSON find_name ERROR_VARIABLE find_name_err GET "${meta_json}" find_package_name)
    if(find_name_err)
        set(find_name "${pkg_key}")
    endif()
    set(${out_name} "${find_name}")
    return(PROPAGATE ${out_name})
endfunction()

function(cdpm_find_package_in_repo package_or_find_name out_found out_pkg_key out_meta_json)
    string(TOLOWER "${package_or_find_name}" requested_key)
    _cdpm_registry_find_canonical("${requested_key}" found meta)
    if(found)
        set(${out_found} TRUE)
        set(${out_pkg_key} "${requested_key}")
        set(${out_meta_json} "${meta}")
        return(PROPAGATE ${out_found} ${out_pkg_key} ${out_meta_json})
    endif()
    _cdpm_registry_find_alias("${requested_key}" found package_key meta)
    set(${out_found} "${found}")
    set(${out_pkg_key} "${package_key}")
    set(${out_meta_json} "${meta}")
    return(PROPAGATE ${out_found} ${out_pkg_key} ${out_meta_json})
endfunction()

# .. rst:
# ``cdpm_get_package_system_dependencies(<pkg_name> <meta_json> <version> <out_json>)``
#
# Returns the canonical effective system dependency map. A per-version declaration replaces the complete
# package-level map; it is not deep-merged.
function(cdpm_get_package_system_dependencies pkg_name meta_json version out_json)
    string(JSON dependencies ERROR_VARIABLE dependencies_err GET "${meta_json}" "system_dependencies")
    if(dependencies_err)
        set(dependencies "{}")
    endif()
    if(NOT version STREQUAL "")
        string(JSON version_dependencies ERROR_VARIABLE version_err GET
            "${meta_json}" "versions" "${version}" "system_dependencies")
        if(NOT version_err)
            set(dependencies "${version_dependencies}")
        endif()
    endif()
    _cdpm_normalize_system_dependencies("${pkg_name}" "${dependencies}" "effective system_dependencies" result)
    set(${out_json} "${result}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``cdpm_find_in_repo(<pkg_name> <out_found> <out_meta_json>)``
#
# Looks up ``<pkg_name>`` (normalized to lower-case) in the merged repository registry
# (``CDPM_MERGED_REPO``). Sets ``<out_found>`` to TRUE/FALSE and, on a hit, ``<out_meta_json>`` to the
# package metadata object; otherwise ``{}``. The first repository that registered the package wins, which
# is already reflected by ``cdpm_load_repo``'s first-registration-wins accumulation.
function(cdpm_find_in_repo pkg_name out_found out_meta_json)
    _cdpm_registry_find_canonical("${pkg_name}" found meta)
    set(${out_found} "${found}")
    set(${out_meta_json} "${meta}")
    return(PROPAGATE ${out_found} ${out_meta_json})
endfunction()

# .. rst:
# ``_cdpm_version_satisfies(<requested> <compat_version> <version> <out_ok>)``
#
# CPS compatibility check: a request ``R`` is satisfied by a chosen package ``version`` when
# ``compat_version <= R <= version``. When the package declares no ``compat_version``, only an exact match
# (``R == version``) qualifies (a conservative default - no implicit backward compatibility). Sets
# ``<out_ok>`` to TRUE/FALSE. Version ranges in the request are out of scope for v1: a single exact version
# token is expected on the right-hand side.
function(_cdpm_version_satisfies requested compat_version version out_ok)
    set(${out_ok} FALSE PARENT_SCOPE)

    if(compat_version STREQUAL "")
        if(requested VERSION_EQUAL "${version}")
            set(${out_ok} TRUE PARENT_SCOPE)
        endif()
        return()
    endif()

    # compat_version <= requested <= version
    if(NOT requested VERSION_LESS "${compat_version}" AND NOT requested VERSION_GREATER "${version}")
        set(${out_ok} TRUE PARENT_SCOPE)
    endif()
endfunction()

# .. rst:
# ``cdpm_resolve_version(<pkg_name> <meta_json> <requested_version>
#                        <out_version> <out_compat_version>)``
#
# Selects the effective version of ``<pkg_name>`` honoring the priority chain and validates it against the
# ``find_package()`` constraint.
#
# Selection priority (high -> low):
#   1. ``CDPM_<PKG>_VERSION`` cache variable (PKG upper-cased; debug/CI)
#   2/3. ``packages.<pkg>.version`` from the effective config (user over project is already resolved by the
#        layer merge; the two are not distinguished here in v1 - the diagnostic source is reported as
#        "config")
#   4. ``cdpm.lock.json`` pin (the cached ``CDPM_LOCKFILE_JSON`` global, when a lockfile was loaded)
#   5. ``meta_json.default_version`` from the repository
#
# The lockfile is treated as a cache of previous resolutions, not a hard constraint. It is therefore skipped
# when a higher-priority source is in effect, and also when the user passes ``--no-lockfile`` on the CLI
# (which sets ``CDPM_SKIP_LOCKFILE``).
#
# The chosen version must exist in ``meta_json.versions``. ``<requested_version>`` (possibly empty) is the
# find_package constraint; if non-empty it is validated via :cmake:command:`_cdpm_version_satisfies`
# against the chosen version's ``compat_version``. A failure is fatal and names the selection source.
#
# Returns the chosen version in ``<out_version>`` and that version's ``compat_version`` (possibly empty) in
# ``<out_compat_version>`` so the provider can answer ``find_package`` with the correct CPS
# ``compat_version``.
function(cdpm_resolve_version pkg_name meta_json requested_version out_version out_compat_version)
    cmake_parse_arguments(arg "HOST" "" "" ${ARGN})
    string(TOLOWER "${pkg_name}" name)
    string(TOUPPER "${pkg_name}" upper)

    # --- Step 1: select the version per priority -----------------------------
    set(selected "")
    set(source "")

    # An explicit CDPM_<PKG>_VERSION cache variable overrides everything, including stale lockfile pins.
    if(DEFINED CDPM_${upper}_VERSION AND NOT CDPM_${upper}_VERSION STREQUAL "")
        set(selected "${CDPM_${upper}_VERSION}")
        set(source "CDPM_${upper}_VERSION cache variable")
    endif()

    if(selected STREQUAL "")
        get_property(eff GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG)
        if(eff)
            string(JSON cfg_ver ERROR_VARIABLE cfg_err GET "${eff}" "packages" "${name}" "version")
            if(NOT cfg_err AND NOT cfg_ver STREQUAL "")
                set(selected "${cfg_ver}")
                set(source "config (cdpm.json/cdpm_user.json)")
            endif()
        endif()
    endif()

    # --- Step 4: a version pinned by the lockfile (lowest priority, skipped when
    # --no-lockfile is in effect or when a higher-priority source already selected) ----
    # Read the cached lockfile JSON directly from the global property so this module needs no dependency
    # on cdpm_lockfile (which itself includes cdpm_config). The property is populated by
    # cdpm_read_lockfile(); absent when no lockfile was loaded, in which case this step is skipped.
    if(selected STREQUAL "" AND NOT CDPM_SKIP_LOCKFILE)
        get_property(lock GLOBAL PROPERTY CDPM_LOCKFILE_JSON)
        if(lock)
            if(arg_HOST)
                set(lock_section host_packages)
            else()
                set(lock_section packages)
            endif()
            string(JSON lock_ver ERROR_VARIABLE lock_err GET "${lock}" "${lock_section}" "${name}" "version")
            if(NOT lock_err AND NOT lock_ver STREQUAL "")
                set(selected "${lock_ver}")
                set(source "cdpm.lock.json")
            endif()
        endif()
    endif()

    if(selected STREQUAL "")
        string(JSON def_ver ERROR_VARIABLE def_err GET "${meta_json}" "default_version")
        if(NOT def_err AND NOT def_ver STREQUAL "")
            set(selected "${def_ver}")
            set(source "repository default_version")
        endif()
    endif()

    if(selected STREQUAL "")
        message(FATAL_ERROR "[cdpm] package '${name}': no version selected and the repository "
            "declares no default_version.")
    endif()

    # --- Step 2: the selected version must exist in the repo -----------------
    string(JSON ver_obj ERROR_VARIABLE vo_err GET "${meta_json}" "versions" "${selected}")
    if(vo_err)
        message(FATAL_ERROR "[cdpm] package '${name}': version '${selected}' (from ${source}) is not "
            "present in the repository's versions table.")
    endif()

    string(JSON compat ERROR_VARIABLE compat_err GET "${ver_obj}" "compat_version")
    if(compat_err)
        set(compat "")
    endif()

    # --- Step 3: validate against the find_package() constraint --------------
    if(NOT requested_version STREQUAL "")
        _cdpm_version_satisfies("${requested_version}" "${compat}" "${selected}" ok)
        if(NOT ok)
            if(compat STREQUAL "")
                set(detail "exact match required (no compat_version declared)")
            else()
                set(detail "allowed range: ${compat} <= R <= ${selected}")
            endif()
            message(FATAL_ERROR "[cdpm] package '${name}': requested version '${requested_version}' "
                "is incompatible with selected '${selected}' (from ${source}); ${detail}.")
        endif()
    endif()

    set(${out_version} "${selected}")
    set(${out_compat_version} "${compat}")
    return(PROPAGATE ${out_version} ${out_compat_version})
endfunction()

# =============================================================================
# Effective per-package sections
# =============================================================================

# .. rst:
# ``_cdpm_effective_package_section(<pkg> <section> <out_json>)``
#
# Computes the effective per-package ``<section>`` (``options`` or ``user``) by deep-merging the global
# section over the package-specific one: the cross-layer machine->project->user precedence is already
# resolved inside ``CDPM_EFFECTIVE_CONFIG``, so here only two scopes remain - global ``<section>``
# (lower precedence) and ``packages.<pkg>.<section>`` (higher). Returns ``{}`` when neither is present. No
# canonicalization here; callers canonicalize once over the combined result.
function(_cdpm_effective_package_section pkg section out_json)
    set(${out_json} "{}" PARENT_SCOPE)

    string(TOLOWER "${pkg}" name)

    get_property(eff_set GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG SET)
    if(NOT eff_set)
        return()
    endif()
    get_property(eff GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG)

    # Global section (lower precedence).
    string(JSON global_sec ERROR_VARIABLE g_err GET "${eff}" "${section}")
    if(g_err)
        set(global_sec "{}")
    endif()

    # Package-specific section (higher precedence).
    string(JSON pkg_sec ERROR_VARIABLE p_err GET "${eff}" "packages" "${name}" "${section}")
    if(p_err)
        set(pkg_sec "{}")
    endif()

    cdpm_merge_json("${global_sec}" "${pkg_sec}" merged)
    set(${out_json} "${merged}" PARENT_SCOPE)
endfunction()

# .. rst:
# ``_cdpm_parse_kv_options(<spec> <out_json>)``
#
# Parses a ``CDPM_<PKG>_OPTIONS`` cache string of the form ``KEY=VAL;KEY2=VAL2`` into a JSON object of
# string values. Empty input yields ``{}``. A token without ``=`` is treated as ``KEY`` with an empty
# string value. Values are stored as JSON strings (CLI overrides are textual).
function(_cdpm_parse_kv_options spec out_json)
    set(result "{}")
    if(NOT spec STREQUAL "")
        foreach(pair IN LISTS spec)
            if(pair STREQUAL "")
                continue()
            endif()
            string(FIND "${pair}" "=" eq)
            if(eq EQUAL -1)
                set(key "${pair}")
                set(val "")
            else()
                string(SUBSTRING "${pair}" 0 ${eq} key)
                math(EXPR vstart "${eq} + 1")
                string(SUBSTRING "${pair}" ${vstart} -1 val)
            endif()
            _cdpm_json_set_safe("${result}" "${key}" "${val}" "STRING" result)
        endforeach()
    endif()
    set(${out_json} "${result}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``cdpm_get_package_options(<pkg_name> <pkg_version> <out_options_json>)``
#
# Computes the effective build options for ``<pkg_name>`` at ``<pkg_version>`` along the vertical
# (low -> high):
#
# #. repository package-level ``options`` (the default for *every* version);
# #. repository ``version_options[]`` whose ``range`` matches ``<pkg_version>`` (in declared order, so a
#    later matching block wins over an earlier one);
# #. repository per-version ``versions.<v>.options`` (a point override for one version);
# #. global + per-package ``options`` from the effective config (via ``_cdpm_effective_package_section``);
# #. ``CDPM_<PKG>_OPTIONS`` cache override (``KEY=VAL;...`` CLI override).
#
# The combined object is canonicalized once (sorted keys, bool->true/false) so it can feed ``config_hash``
# deterministically. The repository metadata is fetched via :cmake:command:`cdpm_find_in_repo`.
function(cdpm_get_package_options pkg_name pkg_version out_options_json)
    string(TOLOWER "${pkg_name}" name)
    string(TOUPPER "${pkg_name}" upper)

    set(effective "{}")
    cdpm_find_in_repo("${name}" found meta)

    if(found)
        # Layer 1: package-level options - default for all versions.
        string(JSON pkg_opts ERROR_VARIABLE po_err GET "${meta}" "options")
        if(NOT po_err)
            cdpm_merge_json("${effective}" "${pkg_opts}" effective)
        endif()

        if(NOT pkg_version STREQUAL "")
            # Layer 2: version_options[] whose range matches this version.
            string(JSON vopts ERROR_VARIABLE vop_err GET "${meta}" "version_options")
            if(NOT vop_err)
                string(JSON vop_type ERROR_VARIABLE vot_err TYPE "${meta}" "version_options")
                if(NOT vot_err AND vop_type STREQUAL "ARRAY")
                    string(JSON vop_count LENGTH "${vopts}")
                    if(vop_count GREATER 0)
                        math(EXPR vop_last "${vop_count} - 1")
                        foreach(i RANGE 0 ${vop_last})
                            string(JSON entry GET "${vopts}" ${i})
                            string(JSON range GET "${entry}" "range")
                            cdpm_version_in_range("${pkg_version}" "${range}" in_range)
                            if(in_range)
                                string(JSON entry_opts GET "${entry}" "options")
                                cdpm_merge_json("${effective}" "${entry_opts}" effective)
                            endif()
                        endforeach()
                    endif()
                endif()
            endif()

            # Layer 3: per-version options - a point override.
            string(JSON ver_opts ERROR_VARIABLE vo_err GET "${meta}" "versions" "${pkg_version}" "options")
            if(NOT vo_err)
                cdpm_merge_json("${effective}" "${ver_opts}" effective)
            endif()
        endif()
    endif()

    # Layer 4: global + per-package options from the effective config.
    _cdpm_effective_package_section("${name}" "options" cfg_opts)
    cdpm_merge_json("${effective}" "${cfg_opts}" effective)

    # Layer 5: CDPM_<PKG>_OPTIONS cache override (highest precedence).
    if(DEFINED CDPM_${upper}_OPTIONS AND NOT CDPM_${upper}_OPTIONS STREQUAL "")
        _cdpm_parse_kv_options("${CDPM_${upper}_OPTIONS}" cli_opts)
        cdpm_merge_json("${effective}" "${cli_opts}" effective)
    endif()

    _cdpm_validate_option_keys("${effective}" "package '${name}' effective options")
    cdpm_canonical_json("${effective}" canonical)
    set(${out_options_json} "${canonical}")
    return(PROPAGATE ${out_options_json})
endfunction()

# .. rst:
# ``cdpm_get_package_build_system_override(<pkg_name> <out_value> <out_found>)``
#
# Reads ``packages.<pkg_name>.build_system`` from the merged user config (``cdpm.json`` layers, NOT the
# package manifest). Returns the lower-cased driver name if set, or sets ``<out_found>`` to FALSE when the
# field is absent or empty. The override is validated against the driver registry via
# :cmake:command:`cdpm_get_build_system`; an unregistered driver raises ``FATAL_ERROR``.
function(cdpm_get_package_build_system_override pkg_name out_value out_found)
    string(TOLOWER "${pkg_name}" name)

    set(${out_value} "")
    set(${out_found} FALSE)

    get_property(eff GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG)
    if(NOT eff)
        return(PROPAGATE ${out_value} ${out_found})
    endif()

    string(JSON bs_override ERROR_VARIABLE bs_err GET "${eff}" "packages" "${name}" "build_system")
    if(bs_err OR bs_override STREQUAL "")
        return(PROPAGATE ${out_value} ${out_found})
    endif()

    string(TOLOWER "${bs_override}" bs_override)

    cdpm_get_build_system("${bs_override}" _ bs_registered)
    if(NOT bs_registered)
        message(FATAL_ERROR "[cdpm] package '${name}': build_system override '${bs_override}' is not a "
            "registered driver.")
    endif()

    set(${out_value} "${bs_override}")
    set(${out_found} TRUE)
    return(PROPAGATE ${out_value} ${out_found})
endfunction()

# .. rst:
# ``cdpm_get_package_user_kv(<pkg_name> <out_tracked_json> <out_untracked_json>)``
#
# Computes the effective user key-value maps for ``<pkg_name>``. The single ``user`` section
# (global + per-package, merged via :cmake:command:`_cdpm_effective_package_section`) is split into two
# flat ``key -> value`` maps by each entry's ``tracked`` flag (default TRUE): tracked entries (feature
# flags, build-affecting) go to ``<out_tracked_json>`` and feed ``config_hash``; untracked entries
# (secrets, tokens) go to ``<out_untracked_json>`` and stay out of the hash. Each entry is expected to be
# an object ``{ "value": ..., "tracked": bool }``; only ``value`` is emitted (so flipping ``tracked`` never
# changes a value's hash contribution). The tracked map is canonicalized; the untracked map is not (never
# hashed).
function(cdpm_get_package_user_kv pkg_name out_tracked_json out_untracked_json)
    string(TOLOWER "${pkg_name}" name)

    _cdpm_effective_package_section("${name}" "user" user_sec)

    set(tracked "{}")
    set(untracked "{}")

    _cdpm_json_foreach("${user_sec}" kv_keys)
    foreach(key IN LISTS kv_keys)
        string(JSON entry GET "${user_sec}" "${key}")

        string(JSON entry_type ERROR_VARIABLE et_err TYPE "${user_sec}" "${key}")
        if(et_err OR NOT entry_type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] package '${name}' user key '${key}': expected an object "
                "{ value, tracked }.")
        endif()

        # value (required) + its JSON type, re-wrapped safely on output.
        _cdpm_json_get("${entry}" "value" val val_type)
        if(val_type STREQUAL "")
            message(FATAL_ERROR "[cdpm] package '${name}' user key '${key}': missing 'value'.")
        endif()

        # tracked flag (default TRUE).
        string(JSON is_tracked ERROR_VARIABLE tr_err GET "${entry}" "tracked")
        if(tr_err)
            set(is_tracked ON)
        endif()

        if(is_tracked)
            _cdpm_json_set_safe("${tracked}" "${key}" "${val}" "${val_type}" tracked)
        else()
            _cdpm_json_set_safe("${untracked}" "${key}" "${val}" "${val_type}" untracked)
        endif()
    endforeach()

    cdpm_canonical_json("${tracked}" tracked_canon)
    set(${out_tracked_json} "${tracked_canon}")
    set(${out_untracked_json} "${untracked}")
    return(PROPAGATE ${out_tracked_json} ${out_untracked_json})
endfunction()

# .. rst:
# ``cdpm_get_package_source(<pkg_name> <meta_json> <version> <out_source_json> <out_dev>)``
#
# Resolves the fetch source for ``<pkg_name>`` at ``<version>``.
#
# By default the source is the committed repository ``source`` from ``<meta_json>`` augmented with the
# version's integrity pin (``rev`` for git, ``sha256`` for url): the result is
# ``{ <source fields...>, "rev"|"sha256": ... }`` and ``<out_dev>`` is ``FALSE``.
#
# If the effective config declares ``packages.<pkg>.source_override`` (only legal from a non-committed
# layer), it is honoured strictly:
#   * top-level ``allow_source_override: true`` must be set - otherwise FATAL;
#   * the override ``type`` must be ``local`` (no remote re-pointing) - else FATAL;
#   * a non-empty ``path`` is required - else FATAL.
# On success it emits a ``STATUS`` "DEV OVERRIDE" line each configure (so the divergence is never silent),
# returns the override object as the source, and sets ``<out_dev>`` ``TRUE`` (the caller records
# ``"dev": true`` in the lockfile so the build is never mistaken for a reproducible one).
function(cdpm_get_package_source pkg_name meta_json version out_source_json out_dev)
    string(TOLOWER "${pkg_name}" name)
    set(${out_dev} FALSE PARENT_SCOPE)

    get_property(eff GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG)
    set(override "")
    if(eff)
        string(JSON override ERROR_VARIABLE ov_err GET "${eff}" "packages" "${name}" "source_override")
        if(ov_err)
            set(override "")
        endif()
    endif()

    # ---- Dev source override path ----
    if(NOT override STREQUAL "")
        string(JSON allow ERROR_VARIABLE allow_err GET "${eff}" "allow_source_override")
        if(allow_err OR NOT allow)
            message(FATAL_ERROR "[cdpm] package '${name}': source_override is present but "
                "'allow_source_override' is not true; refusing to use a local source.")
        endif()

        string(JSON ov_type ERROR_VARIABLE ot_err GET "${override}" "type")
        if(ot_err OR NOT ov_type STREQUAL "local")
            message(FATAL_ERROR "[cdpm] package '${name}': source_override.type must be 'local' "
                "(got '${ov_type}'); remote overrides are not allowed.")
        endif()

        string(JSON ov_path ERROR_VARIABLE op_err GET "${override}" "path")
        if(op_err OR ov_path STREQUAL "")
            message(FATAL_ERROR "[cdpm] package '${name}': source_override (local) requires a "
                "non-empty 'path'.")
        endif()

        message(STATUS "[cdpm] package '${name}': DEV OVERRIDE - using local source '${ov_path}' "
            "(not reproducible; lockfile marked dev).")
        set(${out_source_json} "${override}" PARENT_SCOPE)
        set(${out_dev} TRUE PARENT_SCOPE)
        return()
    endif()

    # ---- Committed repository source path ----
    string(JSON src ERROR_VARIABLE src_err GET "${meta_json}" "source")
    if(src_err)
        message(FATAL_ERROR "[cdpm] package '${name}': repository metadata has no 'source' object.")
    endif()

    string(JSON src_type ERROR_VARIABLE st_err GET "${src}" "type")
    if(NOT st_err AND NOT version STREQUAL "")
        # Fold the version's integrity pin into the source so callers fetch exactly.
        if(src_type STREQUAL "git")
            string(JSON rev ERROR_VARIABLE rev_err GET "${meta_json}" "versions" "${version}" "rev")
            if(NOT rev_err AND NOT rev STREQUAL "")
                _cdpm_json_set_safe("${src}" "rev" "${rev}" "STRING" src)
            endif()
        elseif(src_type STREQUAL "url")
            # Package-level url_template expands {version} and {version_underscored} into a concrete URL.
            string(JSON url_template ERROR_VARIABLE tmpl_err GET "${meta_json}" "source" "url_template")
            if(NOT tmpl_err AND NOT url_template STREQUAL "")
                string(REPLACE "." "_" version_underscored "${version}")
                set(expanded_url "${url_template}")
                string(REPLACE "{version_underscored}" "${version_underscored}" expanded_url "${expanded_url}")
                string(REPLACE "{version}" "${version}" expanded_url "${expanded_url}")
                _cdpm_json_set_safe("${src}" "url" "${expanded_url}" "STRING" src)
            endif()

            # Fold in the version's integrity pin.
            string(JSON sha ERROR_VARIABLE sha_err GET "${meta_json}" "versions" "${version}" "sha256")
            if(NOT sha_err AND NOT sha STREQUAL "")
                _cdpm_json_set_safe("${src}" "sha256" "${sha}" "STRING" src)
            endif()

            # Per-version URL override (takes precedence over url_template).
            string(JSON ver_url ERROR_VARIABLE ver_url_err GET "${meta_json}" "versions" "${version}" "url")
            if(NOT ver_url_err AND NOT ver_url STREQUAL "")
                _cdpm_json_set_safe("${src}" "url" "${ver_url}" "STRING" src)
            endif()
        endif()
    endif()

    set(${out_source_json} "${src}" PARENT_SCOPE)
endfunction()

# .. rst:
# ``_cdpm_user_key_to_cmake(<key> <out_var>)``
#
# Normalizes a dotted user key (``<org>.<key>``, charset ``[a-z0-9_.-]+``) into a CMake-variable suffix:
# upper-cased, with ``.`` and ``-`` folded to ``_``. ``myorg.fips`` -> ``MYORG_FIPS`` (the caller prefixes
# ``CDPM_USER_``). An invalid character is fatal so a malformed key never produces a surprising variable
# name.
function(_cdpm_user_key_to_cmake key out_var)
    if(NOT key MATCHES "^[a-z0-9_.-]+$")
        message(FATAL_ERROR "[cdpm] user key '${key}': only [a-z0-9_.-] are allowed.")
    endif()
    string(TOUPPER "${key}" up)
    string(REGEX REPLACE "[.-]" "_" up "${up}")
    set(${out_var} "${up}")
    return(PROPAGATE ${out_var})
endfunction()

# .. rst:
# ``cdpm_generate_user_file(<pkg_name> <out_path> [TRACKED_HASH <out_var>])``
#
# Generates the single per-package user key-value include file consumed by the package build. The
# effective ``user`` map (global + per-package, tracked and untracked together - the ``tracked`` flag
# governs hashing, not delivery) is written to ``<out_path>`` as a CMake script that a prepared toolchain
# includes via one ``-DCDPM_USER_FILE=<path>``:
#
# .. code-block:: cmake
#
#    set(CDPM_USER_MYORG_FIPS "on")
#    set(CDPM_USER_KEYS "MYORG_FIPS")
#    set(CDPM_USER_JSON "{\"myorg.fips\":\"on\"}")
#
# Keys are normalized via :cmake:command:`_cdpm_user_key_to_cmake`. ``CDPM_USER_JSON`` is assembled by hand
# with quote/backslash escaping because ``STRING_ENCODE`` is 4.3-only and the baseline is 3.25. Values are
# emitted verbatim (the user map carries already-resolved scalar ``value`` payloads).
#
# ``TRACKED_HASH`` optionally returns the SHA-256 of the canonical *tracked* map (the same object that
# feeds ``config_hash``) so the caller can name the file ``<pkg>-<hash>.cmake`` without recomputing it.
function(cdpm_generate_user_file pkg_name out_path)
    cmake_parse_arguments(arg "" "TRACKED_HASH" "" ${ARGN})

    cdpm_get_package_user_kv("${pkg_name}" tracked untracked)

    # Delivery map = tracked + untracked (every key is delivered to the build).
    cdpm_merge_json("${tracked}" "${untracked}" delivery)

    set(lines "# Auto-generated by cdpm. User key-values for package build. Do not edit.")
    set(var_names "")
    set(json "{}")

    _cdpm_json_foreach("${delivery}" keys)
    foreach(key IN LISTS keys)
        _cdpm_json_get("${delivery}" "${key}" val val_type)
        _cdpm_user_key_to_cmake("${key}" var_suffix)
        list(APPEND var_names "${var_suffix}")

        # set(CDPM_USER_<KEY> "<value>") with CMake-string escaping of " and \.
        set(esc "${val}")
        string(REPLACE "\\" "\\\\" esc "${esc}")
        string(REPLACE "\"" "\\\"" esc "${esc}")
        list(APPEND lines "set(CDPM_USER_${var_suffix} \"${esc}\")")

        # Accumulate into CDPM_USER_JSON (string values; re-wrapped via _cdpm_json_set_safe).
        _cdpm_json_set_safe("${json}" "${key}" "${val}" "${val_type}" json)
    endforeach()

    list(JOIN var_names ";" keys_value)
    list(APPEND lines "set(CDPM_USER_KEYS \"${keys_value}\")")

    # Embed CDPM_USER_JSON as a CMake string literal (escape " and \ for the script).
    set(json_literal "${json}")
    string(REPLACE "\\" "\\\\" json_literal "${json_literal}")
    string(REPLACE "\"" "\\\"" json_literal "${json_literal}")
    list(APPEND lines "set(CDPM_USER_JSON \"${json_literal}\")")

    list(JOIN lines "\n" content)
    file(WRITE "${out_path}" "${content}\n")

    if(arg_TRACKED_HASH)
        string(SHA256 thash "${tracked}")
        set(${arg_TRACKED_HASH} "${thash}")
        return(PROPAGATE ${arg_TRACKED_HASH})
    endif()
endfunction()
