# cdpm_uri.cmake — URI parsing for cdpm.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

include(cdpm_utils)

set(__cdpm_uri_builtin_scheme_names
    gh github
    gl gitlab
    bb bitbucket
    cb codeberg
    CACHE INTERNAL "cdpm built-in shortcut scheme names" FORCE
)

# Shortcut registry - flat list `scheme;template;scheme;template;...`
# Stored as a GLOBAL property to avoid polluting the cache.
set_property(GLOBAL PROPERTY __cdpm_uri_shortcut_registry "")

# Setup built-in shortcuts
block(SCOPE_FOR VARIABLES)
    list(APPEND shortcuts
        "gh"        "https://github.com/{path}.git"
        "github"    "https://github.com/{path}.git"
        "gl"        "https://gitlab.com/{path}.git"
        "gitlab"    "https://gitlab.com/{path}.git"
        "bb"        "https://bitbucket.org/{path}.git"
        "bitbucket" "https://bitbucket.org/{path}.git"
        "cb"        "https://codeberg.org/{path}.git"
        "codeberg"  "https://codeberg.org/{path}.git"
    )

    set_property(GLOBAL PROPERTY __cdpm_uri_shortcut_registry "${shortcuts}")
endblock()

# .. rst:
# ``cdpm_register_uri_shortcut(<scheme> <uri_template> [OVERRIDE] [QUIET])``
#
# Registers a user-defined shortcut scheme.
# Use ``{path}`` in ``<uri_template>`` as a placeholder for the scheme-specific part of the URI.
#
# ``OVERRIDE``
#   Allow replacing an existing scheme. Built-in schemes (gh, gl, bb, ...) can only be replaced 
#   when OVERRIDE is explicitly passed. 
#   Without OVERRIDE, attempting to replace any existing scheme is a fatal error.
#
# ``QUIET``
#   When combined with OVERRIDE, silently replace without a warning.
#   Without OVERRIDE, QUIET downgrades the fatal error to a warning and skips registration.
#
# Security note: never pass OVERRIDE based on data read from a package registry 
# or a dependency's CMakeLists.txt — doing so would allow supply-chain redirection attacks.
function(cdpm_register_uri_shortcut scheme uri_template)
    cmake_parse_arguments(arg "OVERRIDE;QUIET" "" "" ${ARGN})

    # Validate uri_template
    if(NOT uri_template MATCHES [[\{path\}]])
        message(FATAL_ERROR "[cdpm] cdpm_register_uri_shortcut: uri_template '${uri_template}' must contain '{path}'!")
    endif()

    string(TOLOWER "${scheme}" scheme_key)

    # Forward OVERRIDE/QUIET only when explicitly requested (avoid passing empty flags).
    set(forward "")
    if(arg_OVERRIDE)
        list(APPEND forward OVERRIDE)
    endif()
    if(arg_QUIET)
        list(APPEND forward QUIET)
    endif()

    _cdpm_kv_registry_set(__cdpm_uri_shortcut_registry "${scheme_key}" "${uri_template}"
        ${forward} BUILTINS ${__cdpm_uri_builtin_scheme_names})
endfunction()

# Guesses resource type from a plain URL. (TODO: maybe this is a bad idea)
# Sets <out_name> in the caller's scope via PROPAGATE.
macro(_cdpm_guess_resource_type uri out_name)
    block(SCOPE_FOR VARIABLES PROPAGATE "${out_name}")
        if("${uri}" MATCHES [[\.(tar\.gz|tar\.bz2|tar\.xz|tar\.zst|tgz|zip|7z)(\?.*)?$]])
            set(${out_name} "ARCHIVE")
        elseif("${uri}" MATCHES [[\.git(/.*)?$]])
            set(${out_name} "GIT_REPO")
        else()
            set(${out_name} "UNKNOWN")
        endif()
    endblock()
endmacro()


set(__cdpm_uri_scheme_regex 
    [=[^([a-zA-Z][a-zA-Z0-9+.-]*):(.*)$]=]
    CACHE INTERNAL "cdpm URI scheme regex" FORCE
)

# .. rst:
# ``cdpm_parse_uri(<uri> PREFIX <prefix>)``
#
# Parses a URI and sets result variables in the caller's scope.
# Supported URI format:  [scheme:]<path>[@ref][#subdir]
#
# Output variables (set with caller-supplied prefix via ``<prefix>``):
#   <prefix>_SCHEME_TYPE   — GIT_SHORTCUT | CUSTOM_SHORTCUT | HTTP | HTTPS | SSH | FILE | PLAIN
#   <prefix>_FULL_URI      — expanded full URI
#   <prefix>_RESOURCE_TYPE — GIT_REPO | ARCHIVE | LOCAL_PATH | UNKNOWN
#   <prefix>_REF           — git ref from @<ref>  (empty if absent)
#   <prefix>_SUBDIR        — subdirectory from #<subdir>  (empty if absent)
function(cdpm_parse_uri uri)
    cmake_parse_arguments(arg "" "PREFIX" "" ${ARGN})
    if(NOT arg_PREFIX)
        message(FATAL_ERROR "[cdpm] cdpm_parse_uri: PREFIX argument is required")
    endif()

    # Step 1: strip trailing #subdir (# is unambiguous in URI)
    if("${uri}" MATCHES [=[^([^#]+)(#.*)?$]=])
        set(no_subdir "${CMAKE_MATCH_1}")
        set(uri_part_subdir "${CMAKE_MATCH_2}")
        if(uri_part_subdir)
            string(SUBSTRING "${uri_part_subdir}" 1 -1 uri_part_subdir)
        endif()
    else()
        message(FATAL_ERROR "[cdpm] Invalid URI: '${uri}'")
    endif()

    # Step 2: split main/ref only when URI has a known explicit scheme.
    # A "scheme" containing a hyphen is an SSH config Host alias, not a real scheme.
    string(TOLOWER "${no_subdir}" no_subdir_lc)
    list(APPEND known_schemes 
        https http ssh git file
    )
    get_property(shortcut_registry GLOBAL PROPERTY __cdpm_uri_shortcut_registry)

    set(has_explicit_scheme FALSE)
    if("${no_subdir_lc}" MATCHES [=[^([a-zA-Z][a-zA-Z0-9+.-]*):]=])
        set(shortcut_candidate "${CMAKE_MATCH_1}")
        # Reject hyphenated candidates — RFC 3986 schemes have no hyphens
        if(NOT "${shortcut_candidate}" MATCHES "-")
            list(FIND shortcut_registry "${shortcut_candidate}" shortcut_idx)
            if(shortcut_idx GREATER_EQUAL 0 OR "${shortcut_candidate}" IN_LIST known_schemes)
                set(has_explicit_scheme TRUE)
            endif()
        endif()
    endif()

    if(has_explicit_scheme)
        if("${no_subdir}" MATCHES [=[^([^@]+)(@(.+))?$]=])
            set(uri_part_main "${CMAKE_MATCH_1}")
            set(uri_part_ref "${CMAKE_MATCH_3}")
        endif()
    else()
        set(uri_part_main "${no_subdir}")
        set(uri_part_ref "")
    endif()

    # Step 3: detect scheme
    block(PROPAGATE scheme_type full_uri resource_type)
        string(TOLOWER "${uri_part_main}" main_lc)

        if(has_explicit_scheme AND "${main_lc}" MATCHES "${__cdpm_uri_scheme_regex}")
            string(TOLOWER "${CMAKE_MATCH_1}" scheme)
            set(specific "${CMAKE_MATCH_2}")

            list(FIND shortcut_registry "${scheme}" shortcut_idx)

            if(shortcut_idx GREATER_EQUAL 0)
                math(EXPR template_idx "${shortcut_idx} + 1")
                list(GET shortcut_registry ${template_idx} template)
                string(REPLACE "{path}" "${specific}" full_uri "${template}")

                if(scheme IN_LIST __cdpm_uri_builtin_scheme_names)
                    set(scheme_type "GIT_SHORTCUT")
                else()
                    set(scheme_type "CUSTOM_SHORTCUT")
                endif()
                set(resource_type "GIT_REPO")
            elseif(scheme STREQUAL "https")
                set(full_uri "${uri_part_main}")
                set(scheme_type "HTTPS")
                _cdpm_guess_resource_type("${full_uri}" resource_type)
            elseif(scheme STREQUAL "http")
                set(full_uri "${uri_part_main}")
                set(scheme_type "HTTP")
                _cdpm_guess_resource_type("${full_uri}" resource_type)
            elseif(scheme MATCHES "^(ssh|git)$")
                set(scheme_type "SSH")
                set(full_uri "${uri_part_main}")
                set(resource_type "GIT_REPO")
            elseif(scheme STREQUAL "file")
                set(scheme_type "FILE")
                set(full_uri "${specific}")
                set(resource_type "LOCAL_PATH")
            else()
                message(FATAL_ERROR "[cdpm] Unknown URI scheme `${scheme}` in '${uri}'!")
            endif()

        else()
            # No explicit scheme — local path or scp-style (user@host:path.git)
            set(scheme_type "PLAIN")
            set(full_uri "${uri_part_main}")
            if("${uri_part_main}" MATCHES "^[^/]+:[^/]")
                set(resource_type "GIT_REPO") # scp-style
            elseif(IS_ABSOLUTE "${uri_part_main}" OR "${uri_part_main}" MATCHES "^[./]")
                set(resource_type "LOCAL_PATH")
            else()
                set(resource_type "UNKNOWN")
            endif()
        endif()
    endblock()

    set(${arg_PREFIX}_SCHEME_TYPE "${scheme_type}")
    set(${arg_PREFIX}_FULL_URI "${full_uri}")
    set(${arg_PREFIX}_RESOURCE_TYPE "${resource_type}")
    set(${arg_PREFIX}_REF "${uri_part_ref}")
    set(${arg_PREFIX}_SUBDIR "${uri_part_subdir}")

    return(PROPAGATE
        ${arg_PREFIX}_SCHEME_TYPE
        ${arg_PREFIX}_FULL_URI
        ${arg_PREFIX}_RESOURCE_TYPE
        ${arg_PREFIX}_REF
        ${arg_PREFIX}_SUBDIR
    )
endfunction()
