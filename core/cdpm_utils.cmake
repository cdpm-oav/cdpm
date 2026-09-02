# cdpm_utils.cmake — Internal helpers shared across cdpm modules.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)
# Modules carry no cmake_minimum_required, so set the policies they rely on explicitly to stay correct
# when included from a bare script under the 3.25 baseline:
#   CMP0057 -- if(... IN_LIST ...) operator;
#   CMP0007 -- list() commands do not silently drop empty elements (index math stays correct).
cmake_policy(SET CMP0057 NEW)
cmake_policy(SET CMP0007 NEW)

include(cdpm_json) # JSON helpers (_cdpm_json_get/_cdpm_json_keys/_cdpm_json_foreach/...) shared across modules.

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
# or a dependency's CMakeLists.txt — that would allow supply-chain redirection.
function(_cdpm_kv_registry_set property_name key value)
    cmake_parse_arguments(arg "OVERRIDE;QUIET" "" "BUILTINS" ${ARGN})

    get_property(registry GLOBAL PROPERTY "${property_name}")
    list(FIND registry "${key}" key_idx)

    if(key_idx GREATER_EQUAL 0)
        if(NOT arg_OVERRIDE)
            if(arg_QUIET)
                message(WARNING "[cdpm] Registry '${property_name}': key '${key}' is already registered — skipping."
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
