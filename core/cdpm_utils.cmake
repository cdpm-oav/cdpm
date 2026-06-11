# cdpm_utils.cmake — Internal helpers shared across cdpm modules.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# .. rst:
# ``_cdpm_json_foreach(<json> <out_keys>)``
#
# Collects the member names of a JSON object into ``<out_keys>`` (a CMake list).
# This is the single guarded entry point for iterating JSON objects; callers run their own ``foreach(key IN LISTS <out_keys>)`` 
# and fetch type/value via ``_cdpm_json_get``.
#
# Safe on empty objects and on non-object / missing input: in those cases the output list is empty and no fatal error is raised 
# (uses ``ERROR_VARIABLE``). Because the keys are copied out first, removing members from the source object inside the loop is safe 
# (indices are not shifted under the iterator).
macro(_cdpm_json_foreach json out_keys)
    block(SCOPE_FOR VARIABLES PROPAGATE "${out_keys}")
        set(${out_keys} "")
        string(JSON len ERROR_VARIABLE err LENGTH "${json}")
        # err is empty on success; "NOTFOUND"/message on empty or non-object input.
        if(NOT err AND len GREATER 0)
            math(EXPR last "${len} - 1")
            foreach(i RANGE 0 ${last})
                string(JSON json_member MEMBER "${json}" ${i})
                list(APPEND ${out_keys} "${json_member}")
            endforeach()
        endif()
    endblock()
endmacro()

# .. rst:
# ``_cdpm_json_get(<json> <key> <out_value> <out_type>)``
#
# Companion to ``_cdpm_json_foreach``: fetches the value and CMake JSON type of a single member. 
# ``<out_type>`` is one of OBJECT | ARRAY | STRING | NUMBER | BOOLEAN | NULL, or empty when the key is absent. 
# ``<out_value>`` is empty when the key is absent. 
# Uses ``ERROR_VARIABLE`` so a missing key never aborts configure.
#
# Note: ``string(JSON ... GET ...)`` returns booleans as ``ON``/``OFF`` on the 3.26 baseline, not ``true``/``false`` — 
# callers that hash values must normalize via ``<out_type>``.
function(_cdpm_json_get json key out_value out_type)
    string(JSON value_type ERROR_VARIABLE type_err TYPE "${json}" "${key}")
    if(type_err)
        set(${out_value} "" PARENT_SCOPE)
        set(${out_type} "" PARENT_SCOPE)
        return()
    endif()

    string(JSON value ERROR_VARIABLE get_err GET "${json}" "${key}")
    if(get_err)
        set(value "")
    endif()

    set(${out_value} "${value}" PARENT_SCOPE)
    set(${out_type} "${value_type}" PARENT_SCOPE)
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

    set(${out_var} "${result}" PARENT_SCOPE)
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
# or a dependency's CMakeLists.txt — that would allow supply-chain redirection.
function(_cdpm_kv_registry_set property_name key value)
    cmake_parse_arguments(arg "OVERRIDE;QUIET" "" "BUILTINS" ${ARGN})

    get_property(registry GLOBAL PROPERTY "${property_name}")
    list(FIND registry "${key}" key_idx)

    if(key_idx GREATER_EQUAL 0)
        if(NOT arg_OVERRIDE)
            if(arg_QUIET)
                message(WARNING "[cdpm] Registry '${property_name}': key '${key}' is already "
                    "registered — skipping. Pass OVERRIDE to replace it.")
                return()
            else()
                message(FATAL_ERROR "[cdpm] Registry '${property_name}': key '${key}' is already "
                    "registered. Pass OVERRIDE to replace it, or QUIET to skip silently.")
            endif()
        endif()

        # OVERRIDE: warn unless QUIET.
        if(NOT arg_QUIET)
            if(key IN_LIST arg_BUILTINS)
                message(WARNING "[cdpm] Overriding built-in registry entry '${key}' in "
                    "'${property_name}'. Ensure the replacement is trusted.")
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
        set(${out_value} "${value}" PARENT_SCOPE)
        set(${out_found} TRUE PARENT_SCOPE)
    else()
        set(${out_value} "" PARENT_SCOPE)
        set(${out_found} FALSE PARENT_SCOPE)
    endif()
endfunction()
