# cdpm_json.cmake - JSON helpers over string(JSON ...).
#
# ``<json>`` and ``<value>`` payloads are positional (a keyword value would be list-split by ARGN when the JSON contains ``;``). 
# ``PATH`` elements and options are keyword arguments.

include_guard(GLOBAL)

if(POLICY CMP0007)
    cmake_policy(SET CMP0007 NEW)
endif()
if(POLICY CMP0057)
    cmake_policy(SET CMP0057 NEW)
endif()
if(POLICY CMP0140)
    cmake_policy(SET CMP0140 NEW)
endif()

# .. rst:
# ``_cdpm_json_array_to_list(<out_list> <json> [PATH <member|index>...])``
#
# Scalar array elements as a CMake list. Elements containing ``;`` are a known limitation.
function(_cdpm_json_array_to_list out_list json)
    cmake_parse_arguments(a "" "" "PATH" ${ARGN})
    set(items "")
    string(JSON n ERROR_VARIABLE err LENGTH "${json}" ${a_PATH})
    if(NOT err AND n GREATER 0)
        math(EXPR last "${n} - 1")
        foreach(i RANGE 0 ${last})
            string(JSON e GET "${json}" ${a_PATH} ${i})
            list(APPEND items "${e}")
        endforeach()
    endif()
    set(${out_list} "${items}")
    return(PROPAGATE ${out_list})
endfunction()

# .. rst:
# ``_cdpm_json_encode_string(<out_var> <raw>)``
#
# Wraps a raw string as a JSON string literal (escapes ``\`` and ``"``). 
# Replacement for ``string(JSON ... STRING_ENCODE ...)`` which only exists on CMake >= 4.3.
function(_cdpm_json_encode_string out_var raw)
    if(CMAKE_VERSION VERSION_GREATER_EQUAL 4.3)
        string(JSON ${out_var} ERROR_VARIABLE err STRING_ENCODE "${raw}")
        if(err)
            set(${out_var} "")
        endif()
    else()
        string(REPLACE "\\" "\\\\" v "${raw}")
        string(REPLACE "\"" "\\\"" v "${v}")
        set(${out_var} "\"${v}\"")
    endif()

    return(PROPAGATE ${out_var})
endfunction()

# .. rst:
# ``_cdpm_json_equal(<out_bool> <json_a> <json_b>)``
#
# Semantic JSON equality (key order / whitespace insensitive); FALSE on invalid input.
function(_cdpm_json_equal out_bool json_a json_b)
    string(JSON eq ERROR_VARIABLE err EQUAL "${json_a}" "${json_b}")
    if(err OR NOT eq)
        set(${out_bool} FALSE)
    else()
        set(${out_bool} TRUE)
    endif()
    return(PROPAGATE ${out_bool})
endfunction()

# .. rst:
# ``_cdpm_json_get(<out_value> <json> [PATH <member|index>...] [OUT_TYPE <var>] [DEFAULT <value>]``
# ``[REQUIRED] [EXPECT_TYPE <t>] [NON_EMPTY] [CONTEXT <msg>])``
#
# Fetches a scalar/element at the path. Booleans come back as ON/OFF on the 3.25 baseline.
# Absent path -> ``DEFAULT`` (empty if unset), unless ``REQUIRED`` (fatal). ``EXPECT_TYPE`` /
# ``NON_EMPTY`` validate and fail with ``[cdpm] <CONTEXT>: ...``.
function(_cdpm_json_get out_value json)
    cmake_parse_arguments(a "REQUIRED;NON_EMPTY" "OUT_TYPE;DEFAULT;EXPECT_TYPE;CONTEXT" "PATH" ${ARGN})
    if(NOT DEFINED a_CONTEXT)
        set(a_CONTEXT "json")
    endif()

    string(JSON vtype ERROR_VARIABLE terr TYPE "${json}" ${a_PATH})
    if(terr)
        if(a_REQUIRED)
            message(FATAL_ERROR "[cdpm] ${a_CONTEXT}: missing '${a_PATH}'.")
        endif()
        set(${out_value} "${a_DEFAULT}")
        if(a_OUT_TYPE)
            set(${a_OUT_TYPE} "")
            return(PROPAGATE ${out_value} ${a_OUT_TYPE})
        endif()
        return(PROPAGATE ${out_value})
    endif()

    if(a_EXPECT_TYPE AND NOT vtype STREQUAL a_EXPECT_TYPE)
        message(FATAL_ERROR "[cdpm] ${a_CONTEXT}: '${a_PATH}' must be ${a_EXPECT_TYPE}, got ${vtype}.")
    endif()

    string(JSON value ERROR_VARIABLE gerr GET "${json}" ${a_PATH})
    if(gerr)
        set(value "")
    endif()
    if(a_NON_EMPTY AND value STREQUAL "")
        message(FATAL_ERROR "[cdpm] ${a_CONTEXT}: '${a_PATH}' must be non-empty.")
    endif()

    set(${out_value} "${value}")
    if(a_OUT_TYPE)
        set(${a_OUT_TYPE} "${vtype}")
        return(PROPAGATE ${out_value} ${a_OUT_TYPE})
    endif()
    return(PROPAGATE ${out_value})
endfunction()

# .. rst:
# ``_cdpm_json_has(<out_bool> <json> [PATH <member|index>...])`` - TRUE when the path resolves.
function(_cdpm_json_has out_bool json)
    cmake_parse_arguments(a "" "" "PATH" ${ARGN})
    string(JSON t ERROR_VARIABLE err TYPE "${json}" ${a_PATH})
    if(err)
        set(${out_bool} FALSE)
    else()
        set(${out_bool} TRUE)
    endif()
    return(PROPAGATE ${out_bool})
endfunction()

# .. rst:
# ``_cdpm_json_keys(<out_list> <json> [PATH <member|index>...])``
#
# Member names of an object as a CMake list (empty on absent/non-object). Safe to mutate the
# source inside the resulting ``foreach`` (keys are copied out first).
function(_cdpm_json_keys out_list json)
    cmake_parse_arguments(a "" "" "PATH" ${ARGN})
    set(keys "")
    string(JSON n ERROR_VARIABLE err LENGTH "${json}" ${a_PATH})
    if(NOT err AND n GREATER 0)
        math(EXPR last "${n} - 1")
        foreach(i RANGE 0 ${last})
            string(JSON k MEMBER "${json}" ${a_PATH} ${i})
            list(APPEND keys "${k}")
        endforeach()
    endif()
    set(${out_list} "${keys}")
    return(PROPAGATE ${out_list})
endfunction()

# .. rst:
# ``_cdpm_json_length(<out_len> <json> [PATH <member|index>...])``
#
# Length of an array/object; 0 when absent or not a container.
function(_cdpm_json_length out_len json)
    cmake_parse_arguments(a "" "" "PATH" ${ARGN})
    string(JSON n ERROR_VARIABLE err LENGTH "${json}" ${a_PATH})
    if(err)
        set(n 0)
    endif()
    set(${out_len} "${n}")
    return(PROPAGATE ${out_len})
endfunction()

# .. rst:
# ``_cdpm_json_remove(<json_var> PATH <member|index>... [REQUIRED] [CONTEXT <msg>])``
#
# Removes an element. Absent path is tolerated unless ``REQUIRED``.
function(_cdpm_json_remove json_var)
    cmake_parse_arguments(a "REQUIRED" "CONTEXT" "PATH" ${ARGN})
    string(JSON updated ERROR_VARIABLE err REMOVE "${${json_var}}" ${a_PATH})
    if(err)
        if(a_REQUIRED)
            if(NOT DEFINED a_CONTEXT)
                set(a_CONTEXT "json")
            endif()
            message(FATAL_ERROR "[cdpm] ${a_CONTEXT}: cannot remove missing '${a_PATH}'.")
        endif()
        return()
    endif()
    set(${json_var} "${updated}")
    return(PROPAGATE ${json_var})
endfunction()

# .. rst:
# ``_cdpm_split_key_operator(<raw_key> <out_key> <out_op>)``
#
# Splits a v1 merge operator suffix off a key. Trailing ``!!`` is an escape for a literal ``!``;
# a single trailing ``!`` yields ``REPLACE``.
function(_cdpm_split_key_operator raw_key out_key out_op)
    if(raw_key MATCHES "!!$")
        string(REGEX REPLACE "!!$" "!" literal "${raw_key}")
        set(${out_key} "${literal}")
        set(${out_op} "")
        return(PROPAGATE ${out_key} ${out_op})
    endif()
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
# ``_cdpm_json_type(<out_type> <json> [PATH <member|index>...])``
#
# Element type: OBJECT|ARRAY|STRING|NUMBER|BOOLEAN|NULL, empty when the path is absent.
function(_cdpm_json_type out_type json)
    cmake_parse_arguments(a "" "" "PATH" ${ARGN})
    string(JSON t ERROR_VARIABLE err TYPE "${json}" ${a_PATH})
    if(err)
        set(t "")
    endif()
    set(${out_type} "${t}")
    return(PROPAGATE ${out_type})
endfunction()

# .. rst:
# ``_cdpm_json_get_members(<out_prefix> <json> KEYS <k>... [PATH ...] [REQUIRED] [NON_EMPTY]``
# ``[EXPECT_TYPE <t>] [CONTEXT <msg>])``
#
# Bulk fetch: for each key sets ``<out_prefix>_<key>`` (value) and ``<out_prefix>_<key>_type``.
function(_cdpm_json_get_members out_prefix json)
    cmake_parse_arguments(a "REQUIRED;NON_EMPTY" "EXPECT_TYPE;CONTEXT" "PATH;KEYS" ${ARGN})
    set(fwd "")
    if(a_REQUIRED)
        list(APPEND fwd REQUIRED)
    endif()
    if(a_NON_EMPTY)
        list(APPEND fwd NON_EMPTY)
    endif()
    if(a_EXPECT_TYPE)
        list(APPEND fwd EXPECT_TYPE "${a_EXPECT_TYPE}")
    endif()
    if(DEFINED a_CONTEXT)
        list(APPEND fwd CONTEXT "${a_CONTEXT}")
    endif()
    set(propagated "")
    foreach(k IN LISTS a_KEYS)
        _cdpm_json_get(${out_prefix}_${k} "${json}" PATH ${a_PATH} ${k}
            OUT_TYPE ${out_prefix}_${k}_type ${fwd}
        )
        list(APPEND propagated ${out_prefix}_${k} ${out_prefix}_${k}_type)
    endforeach()
    return(PROPAGATE ${propagated})
endfunction()

# .. rst:
# ``_cdpm_json_set(<json_var> <value> TYPE <t> [PATH <member|index>...])``
#
# In-place SET that re-wraps ``<value>`` by ``<t>`` into valid JSON. ``STRING`` is quoted/escaped,
# ``BOOLEAN`` normalized ON/OFF->true/false, ``NULL`` -> null, ``NUMBER``/``OBJECT``/``ARRAY``/``RAW``
# inserted verbatim.
function(_cdpm_json_set json_var value)
    cmake_parse_arguments(a "" "TYPE" "PATH" ${ARGN})
    if(a_TYPE STREQUAL "STRING")
        _cdpm_json_encode_string(token "${value}")
    elseif(a_TYPE STREQUAL "BOOLEAN")
        if(value)
            set(token "true")
        else()
            set(token "false")
        endif()
    elseif(a_TYPE STREQUAL "NULL")
        set(token "null")
    else()
        set(token "${value}")
    endif()
    string(JSON updated SET "${${json_var}}" ${a_PATH} "${token}")
    set(${json_var} "${updated}")
    return(PROPAGATE ${json_var})
endfunction()

# .. rst:
# ``_cdpm_json_append(<json_var> <value> TYPE <t> [PATH <member|index>...])``
#
# Appends to the array at ``PATH`` (index == current length). Same value wrapping as ``_cdpm_json_set``.
function(_cdpm_json_append json_var value)
    cmake_parse_arguments(a "" "TYPE" "PATH" ${ARGN})
    string(JSON n ERROR_VARIABLE err LENGTH "${${json_var}}" ${a_PATH})
    if(err)
        set(n 0)
    endif()
    _cdpm_json_set(${json_var} "${value}" TYPE "${a_TYPE}" PATH ${a_PATH} ${n})
    return(PROPAGATE ${json_var})
endfunction()

# .. rst:
# ``_cdpm_json_set_safe(<json> <key> <value> <value_type> <out_json>)`` - single-key shim over
# ``_cdpm_json_set`` (kept for existing call sites).
function(_cdpm_json_set_safe json key value value_type out_json)
    set(work "${json}")
    _cdpm_json_set(work "${value}" TYPE "${value_type}" PATH "${key}")
    set(${out_json} "${work}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``cdpm_canonical_json(<json> <out_json>)``
#
# Canonical form for stable hashing: object keys sorted recursively, booleans re-emitted as
# ``true``/``false`` from their TYPE (GET yields ON/OFF on the 3.25 baseline). Array order kept.
function(cdpm_canonical_json json out_json)
    string(JSON value_type ERROR_VARIABLE type_err TYPE "${json}")
    if(type_err)
        set(${out_json} "${json}")
        return(PROPAGATE ${out_json})
    endif()

    if(value_type STREQUAL "OBJECT")
        _cdpm_json_keys(keys "${json}")
        list(SORT keys)
        set(canonical "{}")
        foreach(key IN LISTS keys)
            _cdpm_json_get(child "${json}" PATH "${key}" OUT_TYPE child_type)
            if(child_type MATCHES [[^(OBJECT|ARRAY)$]])
                cdpm_canonical_json("${child}" child_canonical)
                string(JSON canonical SET "${canonical}" "${key}" "${child_canonical}")
            else()
                _cdpm_json_set(canonical "${child}" TYPE "${child_type}" PATH "${key}")
            endif()
        endforeach()
        set(${out_json} "${canonical}")
        return(PROPAGATE ${out_json})
    endif()

    if(value_type STREQUAL "ARRAY")
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
                    _cdpm_json_set(canonical "${element}" TYPE "${element_type}" PATH ${i})
                endif()
            endforeach()
        endif()
        set(${out_json} "${canonical}")
        return(PROPAGATE ${out_json})
    endif()

    if(value_type STREQUAL "BOOLEAN")
        if(json)
            set(${out_json} "true")
        else()
            set(${out_json} "false")
        endif()
        return(PROPAGATE ${out_json})
    endif()

    set(${out_json} "${json}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``cdpm_merge_json(<base_json> <overlay_json> <out_json>)``
#
# Recursively merges ``overlay`` over ``base``: objects deep-merge, scalars/arrays are replaced.
# The v1 key-suffix operator ``!`` forces replacement of a key (``"key!": null`` removes it).
function(cdpm_merge_json base_json overlay_json out_json)
    string(JSON base_type ERROR_VARIABLE base_err TYPE "${base_json}")
    string(JSON overlay_type ERROR_VARIABLE overlay_err TYPE "${overlay_json}")
    if(overlay_err OR NOT overlay_type STREQUAL "OBJECT" OR base_err OR NOT base_type STREQUAL "OBJECT")
        set(${out_json} "${overlay_json}")
        return(PROPAGATE ${out_json})
    endif()

    set(result "${base_json}")
    _cdpm_json_keys(overlay_keys "${overlay_json}")
    foreach(raw_key IN LISTS overlay_keys)
        _cdpm_split_key_operator("${raw_key}" key op)
        _cdpm_json_get(overlay_value "${overlay_json}" PATH "${raw_key}" OUT_TYPE overlay_value_type)

        if(op STREQUAL "REPLACE")
            if(overlay_value_type STREQUAL "NULL")
                _cdpm_json_remove(result PATH "${key}")
            else()
                _cdpm_json_set(result "${overlay_value}" TYPE "${overlay_value_type}" PATH "${key}")
            endif()
            continue()
        endif()

        _cdpm_json_get(base_value "${result}" PATH "${key}" OUT_TYPE base_value_type)
        if(overlay_value_type STREQUAL "OBJECT" AND base_value_type STREQUAL "OBJECT")
            cdpm_merge_json("${base_value}" "${overlay_value}" merged_child)
            string(JSON result SET "${result}" "${key}" "${merged_child}")
        else()
            _cdpm_json_set(result "${overlay_value}" TYPE "${overlay_value_type}" PATH "${key}")
        endif()
    endforeach()

    set(${out_json} "${result}")
    return(PROPAGATE ${out_json})
endfunction()
