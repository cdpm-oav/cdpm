# cdpm_lockfile.cmake - Read/write of cdpm.lock.json (the resolved-dependency lockfile).
#
# The lockfile pins the fully resolved dependency graph for reproducible builds and as the artifact a
# future `cmake provision` step consumes. It is committed to VCS. Layout (lock_schema 1):
#
#   {
#     "cdpm_version": "0.0.1",
#     "lock_schema": 1,
#     "packages": {
#       "<pkg>": {
#         "version": "...",
#         "config_hash": "...",
#         "source_url": "...",          # git + url sources
#         "git_commit": "...",          # git sources only
#         "source_sha256": "...",       # url sources only
#         "dependencies": {},           # resolved transitive slice (v1: empty)
#         "dev": false                  # true when a local source_override is in effect
#       }
#     },
#     "repos": [ { "url": "...", "baseline": "<40-hex>" } ]
#   }
#
# install_dir is deliberately NOT stored: it is derived as <store>/<pkg>/<config_hash>, keeping the
# lockfile portable across machines.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# Canonical JSON + the type-safe JSON setter (booleans, string quoting) live in cdpm_config.
include(cdpm_config)
include(cdpm_version)

# .. rst:
# ``_cdpm_lockfile_default_path(<out_var>)``
#
# Returns the default lockfile path (``${CMAKE_SOURCE_DIR}/cdpm.lock.json``).
function(_cdpm_lockfile_default_path out_var)
    set(${out_var} "${CMAKE_SOURCE_DIR}/cdpm.lock.json")
    return(PROPAGATE ${out_var})
endfunction()

# .. rst:
# ``_cdpm_lockfile_skeleton(<out_json>)``
#
# Returns an empty lockfile object carrying the schema header (``cdpm_version``, ``lock_schema``, an empty
# ``packages`` object and an empty ``repos`` array).
function(_cdpm_lockfile_skeleton out_json)
    _cdpm_get_version(ver)
    set(skeleton "{}")
    _cdpm_json_set_safe("${skeleton}" "cdpm_version" "${ver}" "STRING" skeleton)
    string(JSON skeleton SET "${skeleton}" "lock_schema" "1")
    string(JSON skeleton SET "${skeleton}" "packages" "{}")
    string(JSON skeleton SET "${skeleton}" "repos" "[]")
    set(${out_json} "${skeleton}")
    return(PROPAGATE ${out_json})
endfunction()

# .. rst:
# ``cdpm_read_lockfile([PATH <path>])``
#
# Loads the lockfile from ``<path>`` (default ``${CMAKE_SOURCE_DIR}/cdpm.lock.json``) and caches its JSON
# string in the ``CDPM_LOCKFILE_JSON`` global property, with the resolved path in ``CDPM_LOCKFILE_PATH`` and
# a ``CDPM_LOCKFILE_LOADED`` guard. A missing file is not an error: the cache is seeded with the empty
# schema skeleton so writers can extend it. Malformed JSON is fatal.
function(cdpm_read_lockfile)
    cmake_parse_arguments(arg "" "PATH" "" ${ARGN})

    if(DEFINED arg_PATH AND NOT arg_PATH STREQUAL "")
        set(path "${arg_PATH}")
    else()
        _cdpm_lockfile_default_path(path)
    endif()

    if(EXISTS "${path}")
        file(READ "${path}" content)
        string(JSON type ERROR_VARIABLE type_err TYPE "${content}")
        if(type_err OR NOT type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] lockfile '${path}' is not a JSON object: ${type_err}")
        endif()
    else()
        _cdpm_lockfile_skeleton(content)
    endif()

    set_property(GLOBAL PROPERTY CDPM_LOCKFILE_JSON "${content}")
    set_property(GLOBAL PROPERTY CDPM_LOCKFILE_PATH "${path}")
    set_property(GLOBAL PROPERTY CDPM_LOCKFILE_LOADED TRUE)
endfunction()

# .. rst:
# ``_cdpm_lockfile_ensure_loaded()``
#
# Loads the lockfile from the default path once if it has not been loaded yet (idempotent guard over
# :cmake:command:`cdpm_read_lockfile`).
macro(_cdpm_lockfile_ensure_loaded)
    get_property(_cdpm_lf_loaded GLOBAL PROPERTY CDPM_LOCKFILE_LOADED)
    if(NOT _cdpm_lf_loaded)
        cdpm_read_lockfile()
    endif()
    unset(_cdpm_lf_loaded)
endmacro()

# .. rst:
# ``cdpm_lockfile_get(<pkg_name> <out_found> <out_entry_json>)``
#
# Looks up ``<pkg_name>`` (lower-cased) in the cached lockfile. Sets ``<out_found>`` TRUE/FALSE and, on a
# hit, returns the package entry object in ``<out_entry_json>`` (``{}`` on a miss). Loads the lockfile on
# demand if not already cached.
function(cdpm_lockfile_get pkg_name out_found out_entry_json)
    _cdpm_lockfile_ensure_loaded()
    string(TOLOWER "${pkg_name}" name)

    get_property(lock GLOBAL PROPERTY CDPM_LOCKFILE_JSON)
    set(${out_found} FALSE PARENT_SCOPE)
    set(${out_entry_json} "{}" PARENT_SCOPE)

    if(NOT lock)
        return()
    endif()

    string(JSON entry ERROR_VARIABLE entry_err GET "${lock}" "packages" "${name}")
    if(entry_err)
        return()
    endif()

    set(${out_found} TRUE PARENT_SCOPE)
    set(${out_entry_json} "${entry}" PARENT_SCOPE)
endfunction()

# .. rst:
# ``cdpm_write_lockfile(<pkg_name> <version> <config_hash> <source_json> <dev>)``
#
# Records (or replaces) the ``<pkg_name>`` entry in the lockfile and persists the file. ``<source_json>`` is
# the normalized source object from :cmake:command:`cdpm_get_package_source` /
# :cmake:command:`cdpm_prepare_source`; the integrity fields are extracted from it by type:
#
# * ``git``   -> ``source_url`` + ``git_commit`` (from ``url`` / ``rev``);
# * ``url``   -> ``source_url`` + ``source_sha256`` (from ``url`` / ``sha256``);
# * ``local`` -> no integrity fields (a dev source is not reproducible).
#
# ``<dev>`` (the ``out_dev`` flag) is stored verbatim as a JSON boolean. ``dependencies`` is written as an
# empty object in v1 (the resolved transitive slice lands with transitive-dependency support). The file is
# rewritten in canonical form (sorted keys) for clean VCS diffs. Loads the lockfile on demand first.
function(cdpm_write_lockfile pkg_name version config_hash source_json dev)
    _cdpm_lockfile_ensure_loaded()
    string(TOLOWER "${pkg_name}" name)

    get_property(lock GLOBAL PROPERTY CDPM_LOCKFILE_JSON)
    if(NOT lock)
        _cdpm_lockfile_skeleton(lock)
    endif()

    # Build the package entry.
    set(entry "{}")
    _cdpm_json_set_safe("${entry}" "version"      "${version}"     "STRING" entry)
    _cdpm_json_set_safe("${entry}" "config_hash"  "${config_hash}" "STRING" entry)

    string(JSON src_type ERROR_VARIABLE st_err TYPE "${source_json}")
    if(NOT st_err)
        string(JSON src_kind ERROR_VARIABLE sk_err GET "${source_json}" "type")
        if(sk_err)
            set(src_kind "")
        endif()

        if(src_kind STREQUAL "git")
            string(JSON url ERROR_VARIABLE u_err GET "${source_json}" "url")
            string(JSON rev ERROR_VARIABLE r_err GET "${source_json}" "rev")
            if(NOT u_err)
                _cdpm_json_set_safe("${entry}" "source_url" "${url}" "STRING" entry)
            endif()
            if(NOT r_err)
                _cdpm_json_set_safe("${entry}" "git_commit" "${rev}" "STRING" entry)
            endif()
        elseif(src_kind STREQUAL "url")
            string(JSON url ERROR_VARIABLE u_err GET "${source_json}" "url")
            string(JSON sha ERROR_VARIABLE s_err GET "${source_json}" "sha256")
            if(NOT u_err)
                _cdpm_json_set_safe("${entry}" "source_url" "${url}" "STRING" entry)
            endif()
            if(NOT s_err)
                _cdpm_json_set_safe("${entry}" "source_sha256" "${sha}" "STRING" entry)
            endif()
        endif()
        # local: no integrity fields recorded (dev sources are not reproducible).
    endif()

    string(JSON entry SET "${entry}" "dependencies" "{}")
    _cdpm_json_set_safe("${entry}" "dev" "${dev}" "BOOLEAN" entry)

    # Merge the entry into the packages object and persist.
    string(JSON lock SET "${lock}" "packages" "${name}" "${entry}")
    cdpm_canonical_json("${lock}" lock)

    get_property(path GLOBAL PROPERTY CDPM_LOCKFILE_PATH)
    if(NOT path)
        _cdpm_lockfile_default_path(path)
    endif()
    file(WRITE "${path}" "${lock}\n")

    set_property(GLOBAL PROPERTY CDPM_LOCKFILE_JSON "${lock}")
endfunction()

# .. rst:
# ``cdpm_lockfile_record_repos()``
#
# Records the repository baseline pins (``repos[]`` with ``url`` + ``baseline``) from the effective config's
# ``CDPM_REPO_JSON`` into the cached lockfile and persists the file. Only ``kind=git`` repos carry a
# baseline; ``kind=file`` repos are skipped (no remote pin to record). A no-op when no git repos are
# declared. Loads the lockfile on demand first.
function(cdpm_lockfile_record_repos)
    _cdpm_lockfile_ensure_loaded()

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

    set(out_repos "[]")
    math(EXPR last "${repos_len} - 1")
    foreach(i RANGE 0 ${last})
        string(JSON entry GET "${repos}" ${i})

        string(JSON kind ERROR_VARIABLE kind_err GET "${entry}" "kind")
        if(kind_err OR NOT kind STREQUAL "git")
            continue()
        endif()

        string(JSON url ERROR_VARIABLE u_err GET "${entry}" "url")
        string(JSON baseline ERROR_VARIABLE b_err GET "${entry}" "baseline")
        if(u_err OR b_err)
            continue()
        endif()

        set(rec "{}")
        _cdpm_json_set_safe("${rec}" "url" "${url}" "STRING" rec)
        _cdpm_json_set_safe("${rec}" "baseline" "${baseline}" "STRING" rec)

        string(JSON out_len LENGTH "${out_repos}")
        string(JSON out_repos SET "${out_repos}" ${out_len} "${rec}")
    endforeach()

    get_property(lock GLOBAL PROPERTY CDPM_LOCKFILE_JSON)
    if(NOT lock)
        _cdpm_lockfile_skeleton(lock)
    endif()
    string(JSON lock SET "${lock}" "repos" "${out_repos}")
    cdpm_canonical_json("${lock}" lock)

    get_property(path GLOBAL PROPERTY CDPM_LOCKFILE_PATH)
    if(NOT path)
        _cdpm_lockfile_default_path(path)
    endif()
    file(WRITE "${path}" "${lock}\n")

    set_property(GLOBAL PROPERTY CDPM_LOCKFILE_JSON "${lock}")
endfunction()
