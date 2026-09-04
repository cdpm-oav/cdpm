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
#         "dependencies": {},           # direct managed identity map
#         "system_dependencies": {},    # direct system identity map, when declared
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
cmake_policy(SET CMP0057 NEW)

# Canonical JSON + the type-safe JSON setter (booleans, string quoting) live in cdpm_config.
include(cdpm_config)
include(cdpm_version)
include(cdpm_context)

# .. rst:
# ``_cdpm_lockfile_default_path(<out_var>)``
#
# Returns the lockfile path. An explicit ``CDPM_LOCKFILE_PATH`` cache variable wins; otherwise the
# default ``<project>/cdpm.lock.json`` is used.
function(_cdpm_lockfile_default_path out_var)
    if(DEFINED CDPM_LOCKFILE_PATH AND NOT CDPM_LOCKFILE_PATH STREQUAL "")
        set(${out_var} "${CDPM_LOCKFILE_PATH}")
    else()
        _cdpm_resolve_project_dir(project_dir)
        set(${out_var} "${project_dir}/cdpm.lock.json")
    endif()
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
    string(JSON skeleton SET "${skeleton}" "host_packages" "{}")
    string(JSON skeleton SET "${skeleton}" "repos" "[]")
    set(${out_json} "${skeleton}")
    return(PROPAGATE ${out_json})
endfunction()

# Validates the structural lock schema without imposing source reproducibility policy.
function(_cdpm_lockfile_validate lock path)
    string(JSON lock_type ERROR_VARIABLE lock_type_err TYPE "${lock}")
    if(lock_type_err OR NOT lock_type STREQUAL "OBJECT")
        message(FATAL_ERROR "[cdpm] lockfile '${path}' must be a JSON object.")
    endif()
    string(JSON schema ERROR_VARIABLE schema_err GET "${lock}" lock_schema)
    string(JSON schema_type ERROR_VARIABLE schema_type_err TYPE "${lock}" lock_schema)
    if(schema_err OR schema_type_err OR NOT schema_type STREQUAL "NUMBER" OR NOT schema EQUAL 1)
        message(FATAL_ERROR "[cdpm] lockfile '${path}': lock_schema must be the number 1.")
    endif()
    foreach(section IN ITEMS packages host_packages)
        string(JSON packages_type ERROR_VARIABLE packages_err TYPE "${lock}" "${section}")
        if(packages_err OR NOT packages_type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] lockfile '${path}': ${section} must be an object.")
        endif()
        string(JSON packages GET "${lock}" "${section}")
        _cdpm_json_keys(package_names "${packages}")
        foreach(package_name IN LISTS package_names)
        string(JSON entry_type TYPE "${packages}" "${package_name}")
        if(NOT entry_type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] lockfile '${path}': package '${package_name}' entry must be an object.")
        endif()
        string(JSON entry GET "${packages}" "${package_name}")
        foreach(field IN ITEMS version config_hash)
            string(JSON value ERROR_VARIABLE value_err GET "${entry}" "${field}")
            string(JSON value_type ERROR_VARIABLE value_type_err TYPE "${entry}" "${field}")
            if(value_err OR value_type_err OR NOT value_type STREQUAL "STRING" OR value STREQUAL "")
                message(FATAL_ERROR "[cdpm] lockfile '${path}': package '${package_name}.${field}' must be a "
                    "non-empty string.")
            endif()
        endforeach()
        foreach(dependency_field IN ITEMS dependencies host_dependencies)
            string(JSON dependencies_type ERROR_VARIABLE dependencies_err TYPE "${entry}" "${dependency_field}")
            if(NOT dependencies_err AND NOT dependencies_type STREQUAL "OBJECT")
                message(FATAL_ERROR "[cdpm] lockfile '${path}': ${section} package '${package_name}."
                    "${dependency_field}' must be an object.")
            endif()
        endforeach()
        string(JSON dev_type ERROR_VARIABLE dev_err TYPE "${entry}" dev)
        if(dev_err OR NOT dev_type STREQUAL "BOOLEAN")
            message(FATAL_ERROR "[cdpm] lockfile '${path}': package '${package_name}.dev' must be a boolean.")
        endif()
        string(JSON system_type ERROR_VARIABLE system_err TYPE "${entry}" system_dependencies)
        if(NOT system_err AND NOT system_type STREQUAL "OBJECT")
            message(FATAL_ERROR "[cdpm] lockfile '${path}': package '${package_name}.system_dependencies' must "
                "be an object.")
        endif()

        foreach(dependency_field IN ITEMS dependencies host_dependencies)
            string(JSON dependencies ERROR_VARIABLE dependencies_err GET "${entry}" "${dependency_field}")
            if(dependencies_err)
                continue()
            endif()
            _cdpm_json_keys(dependency_names "${dependencies}")
            foreach(dependency_name IN LISTS dependency_names)
            string(JSON identity_type TYPE "${dependencies}" "${dependency_name}")
            if(NOT identity_type STREQUAL "OBJECT")
                message(FATAL_ERROR "[cdpm] lockfile '${path}': dependency identity '${package_name}."
                    "${dependency_name}' must be an object.")
            endif()
            string(JSON identity GET "${dependencies}" "${dependency_name}")
            foreach(field IN ITEMS package version config_hash)
                string(JSON value ERROR_VARIABLE value_err GET "${identity}" "${field}")
                string(JSON value_type ERROR_VARIABLE value_type_err TYPE "${identity}" "${field}")
                if(value_err OR value_type_err OR NOT value_type STREQUAL "STRING" OR value STREQUAL "")
                    message(FATAL_ERROR "[cdpm] lockfile '${path}': dependency identity '${package_name}."
                        "${dependency_name}.${field}' must be a non-empty string.")
                endif()
            endforeach()
            string(JSON components_type ERROR_VARIABLE components_err TYPE "${identity}" components)
            if(NOT components_err AND NOT components_type STREQUAL "ARRAY")
                message(FATAL_ERROR "[cdpm] lockfile '${path}': dependency identity '${package_name}."
                    "${dependency_name}.components' must be an array.")
            endif()
            endforeach()
        endforeach()
        endforeach()
    endforeach()

    string(JSON repos_type ERROR_VARIABLE repos_err TYPE "${lock}" repos)
    if(repos_err OR NOT repos_type STREQUAL "ARRAY")
        message(FATAL_ERROR "[cdpm] lockfile '${path}': repos must be an array.")
    endif()
    string(JSON repo_count LENGTH "${lock}" repos)
    if(repo_count GREATER 0)
        math(EXPR repo_last "${repo_count} - 1")
        foreach(i RANGE 0 ${repo_last})
            string(JSON repo_type TYPE "${lock}" repos ${i})
            if(NOT repo_type STREQUAL "OBJECT")
                message(FATAL_ERROR "[cdpm] lockfile '${path}': repos[${i}] must be an object.")
            endif()
            foreach(field IN ITEMS url baseline)
                string(JSON value ERROR_VARIABLE value_err GET "${lock}" repos ${i} "${field}")
                string(JSON value_type ERROR_VARIABLE value_type_err TYPE "${lock}" repos ${i} "${field}")
                if(value_err OR value_type_err OR NOT value_type STREQUAL "STRING" OR value STREQUAL "")
                    message(FATAL_ERROR "[cdpm] lockfile '${path}': repos[${i}].${field} must be a non-empty string.")
                endif()
                if(field STREQUAL "baseline")
                    string(LENGTH "${value}" baseline_length)
                    if(NOT baseline_length EQUAL 40 OR NOT value MATCHES [[^[0-9a-fA-F]+$]])
                        message(FATAL_ERROR "[cdpm] lockfile '${path}': repos[${i}].baseline must be a 40-hex SHA.")
                    endif()
                endif()
            endforeach()
        endforeach()
    endif()
endfunction()

# .. rst:
# ``cdpm_read_lockfile([PATH <path>])``
#
# Loads the lockfile from ``<path>`` (default ``<project>/cdpm.lock.json``) and caches its JSON
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
        _cdpm_lockfile_validate("${content}" "${path}")
    else()
        _cdpm_lockfile_skeleton(content)
    endif()

    set_property(GLOBAL PROPERTY CDPM_LOCKFILE_JSON "${content}")
    set_property(GLOBAL PROPERTY CDPM_LOCKFILE_PATH "${path}")
    set_property(GLOBAL PROPERTY CDPM_LOCKFILE_LOADED TRUE)
endfunction()

# Returns graph roots and rejects dangling dependency references or a non-empty rootless graph.
function(_cdpm_lockfile_get_roots lock out_roots)
    string(JSON packages GET "${lock}" packages)
    _cdpm_json_keys(package_names "${packages}")
    set(child_names "")
    foreach(package_name IN LISTS package_names)
        string(JSON dependencies ERROR_VARIABLE dependencies_err GET "${packages}" "${package_name}" dependencies)
        if(dependencies_err)
            set(dependency_names "")
        else()
            _cdpm_json_keys(dependency_names "${dependencies}")
        endif()
        foreach(dependency_name IN LISTS dependency_names)
            string(JSON child_name GET "${dependencies}" "${dependency_name}" package)
            string(TOLOWER "${child_name}" child_name)
            string(JSON child_entry ERROR_VARIABLE child_err GET "${packages}" "${child_name}")
            if(child_err)
                message(FATAL_ERROR "[cdpm] lockfile dependency '${package_name}' references missing package "
                    "'${child_name}'.")
            endif()
            list(APPEND child_names "${child_name}")
        endforeach()
        string(JSON host_dependencies ERROR_VARIABLE host_dependencies_err GET "${packages}" "${package_name}" host_dependencies)
        if(host_dependencies_err)
            continue()
        endif()
        _cdpm_json_keys(host_dependency_names "${host_dependencies}")
        foreach(dependency_name IN LISTS host_dependency_names)
            string(JSON child_name GET "${host_dependencies}" "${dependency_name}" package)
            string(TOLOWER "${child_name}" child_name)
            string(JSON child_entry ERROR_VARIABLE child_err GET "${lock}" host_packages "${child_name}")
            if(child_err)
                message(FATAL_ERROR "[cdpm] lockfile host dependency '${package_name}' references missing host "
                    "package '${child_name}'.")
            endif()
        endforeach()
    endforeach()
    string(JSON host_packages GET "${lock}" host_packages)
    _cdpm_json_keys(host_package_names "${host_packages}")
    foreach(package_name IN LISTS host_package_names)
        string(JSON target_dependencies ERROR_VARIABLE target_dependencies_err GET "${host_packages}" "${package_name}" dependencies)
        if(target_dependencies_err)
            set(target_count 0)
        else()
            string(JSON target_count LENGTH "${target_dependencies}")
        endif()
        if(target_count GREATER 0)
            message(FATAL_ERROR "[cdpm] lockfile host package '${package_name}' contains target dependencies.")
        endif()
        string(JSON host_dependencies ERROR_VARIABLE host_dependencies_err GET "${host_packages}" "${package_name}" host_dependencies)
        if(host_dependencies_err)
            continue()
        endif()
        _cdpm_json_keys(dependency_names "${host_dependencies}")
        foreach(dependency_name IN LISTS dependency_names)
            string(JSON child_name GET "${host_dependencies}" "${dependency_name}" package)
            string(TOLOWER "${child_name}" child_name)
            string(JSON child_entry ERROR_VARIABLE child_err GET "${host_packages}" "${child_name}")
            if(child_err)
                message(FATAL_ERROR "[cdpm] lockfile host dependency '${package_name}' references missing host "
                    "package '${child_name}'.")
            endif()
        endforeach()
    endforeach()
    list(REMOVE_DUPLICATES child_names)
    set(roots "")
    foreach(package_name IN LISTS package_names)
        if(NOT package_name IN_LIST child_names)
            list(APPEND roots "${package_name}")
        endif()
    endforeach()
    if(package_names AND NOT roots)
        message(FATAL_ERROR "[cdpm] lockfile graph has no roots; it is cyclic or malformed.")
    endif()
    set(${out_roots} "${roots}")
    return(PROPAGATE ${out_roots})
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
    cmake_parse_arguments(arg "HOST" "" "" ${ARGN})
    _cdpm_lockfile_ensure_loaded()
    string(TOLOWER "${pkg_name}" name)

    get_property(lock GLOBAL PROPERTY CDPM_LOCKFILE_JSON)
    set(${out_found} FALSE PARENT_SCOPE)
    set(${out_entry_json} "{}" PARENT_SCOPE)

    if(NOT lock)
        return()
    endif()

    if(arg_HOST)
        set(section host_packages)
    else()
        set(section packages)
    endif()
    string(JSON entry ERROR_VARIABLE entry_err GET "${lock}" "${section}" "${name}")
    if(entry_err)
        return()
    endif()

    set(${out_found} TRUE PARENT_SCOPE)
    set(${out_entry_json} "${entry}" PARENT_SCOPE)
endfunction()

# .. rst:
# ``_cdpm_lockfile_compose_entry(<version> <hash> <source_json> <dev> <out_entry>
#                                [DEPENDENCIES <json>] [SYSTEM_IDENTITIES <json>])``
function(_cdpm_lockfile_compose_entry version config_hash source_json dev out_entry)
    cmake_parse_arguments(arg "" "DEPENDENCIES;HOST_DEPENDENCIES;SYSTEM_IDENTITIES" "" ${ARGN})
    set(entry "{}")
    _cdpm_json_set_safe("${entry}" version "${version}" STRING entry)
    _cdpm_json_set_safe("${entry}" config_hash "${config_hash}" STRING entry)

    string(JSON src_kind ERROR_VARIABLE src_kind_err GET "${source_json}" type)
    if(NOT src_kind_err)
        if(src_kind STREQUAL "local")
            set(dev TRUE)
        elseif(src_kind STREQUAL "git")
            string(JSON url ERROR_VARIABLE url_err GET "${source_json}" url)
            string(JSON rev ERROR_VARIABLE rev_err GET "${source_json}" rev)
            if(NOT url_err)
                _cdpm_json_set_safe("${entry}" source_url "${url}" STRING entry)
            endif()
            if(NOT rev_err)
                _cdpm_json_set_safe("${entry}" git_commit "${rev}" STRING entry)
            endif()
        elseif(src_kind STREQUAL "url")
            string(JSON url ERROR_VARIABLE url_err GET "${source_json}" url)
            string(JSON sha ERROR_VARIABLE sha_err GET "${source_json}" sha256)
            if(NOT url_err)
                _cdpm_json_set_safe("${entry}" source_url "${url}" STRING entry)
            endif()
            if(NOT sha_err)
                _cdpm_json_set_safe("${entry}" source_sha256 "${sha}" STRING entry)
            endif()
        endif()
    endif()

    if(DEFINED arg_DEPENDENCIES)
        cdpm_canonical_json("${arg_DEPENDENCIES}" dependencies)
        string(JSON entry SET "${entry}" dependencies "${dependencies}")
    else()
        string(JSON entry SET "${entry}" dependencies "{}")
    endif()
    if(DEFINED arg_HOST_DEPENDENCIES)
        cdpm_canonical_json("${arg_HOST_DEPENDENCIES}" host_dependencies)
        string(JSON entry SET "${entry}" host_dependencies "${host_dependencies}")
    else()
        string(JSON entry SET "${entry}" host_dependencies "{}")
    endif()
    if(DEFINED arg_SYSTEM_IDENTITIES)
        cdpm_canonical_json("${arg_SYSTEM_IDENTITIES}" system_identities)
        string(JSON entry SET "${entry}" system_dependencies "${system_identities}")
    endif()
    _cdpm_json_set_safe("${entry}" dev "${dev}" BOOLEAN entry)
    cdpm_canonical_json("${entry}" entry)
    set(${out_entry} "${entry}")
    return(PROPAGATE ${out_entry})
endfunction()

function(_cdpm_lockfile_persist lock)
    get_property(path GLOBAL PROPERTY CDPM_LOCKFILE_PATH)
    if(NOT path)
        _cdpm_lockfile_default_path(path)
    endif()
    cmake_path(GET path PARENT_PATH parent)
    file(MAKE_DIRECTORY "${parent}")
    set(temporary "${path}.tmp")
    file(WRITE "${temporary}" "${lock}\n")
    file(RENAME "${temporary}" "${path}")
    set_property(GLOBAL PROPERTY CDPM_LOCKFILE_JSON "${lock}")
endfunction()

# Atomically merges a package-entry map into the loaded lockfile in one write.
function(_cdpm_lockfile_commit_entries entries)
    cmake_parse_arguments(arg "" "HOST_ENTRIES;REPOS" "" ${ARGN})
    _cdpm_lockfile_ensure_loaded()
    get_property(lock GLOBAL PROPERTY CDPM_LOCKFILE_JSON)
    if(NOT lock)
        _cdpm_lockfile_skeleton(lock)
    endif()
    _cdpm_json_keys(package_names "${entries}")
    foreach(package_name IN LISTS package_names)
        string(JSON entry GET "${entries}" "${package_name}")
        string(JSON lock SET "${lock}" packages "${package_name}" "${entry}")
    endforeach()
    if(DEFINED arg_HOST_ENTRIES)
        _cdpm_json_keys(host_package_names "${arg_HOST_ENTRIES}")
        foreach(package_name IN LISTS host_package_names)
            string(JSON entry GET "${arg_HOST_ENTRIES}" "${package_name}")
            string(JSON lock SET "${lock}" host_packages "${package_name}" "${entry}")
        endforeach()
    endif()
    if(DEFINED arg_REPOS)
        string(JSON lock SET "${lock}" repos "${arg_REPOS}")
    endif()
    cdpm_canonical_json("${lock}" lock)
    _cdpm_lockfile_persist("${lock}")
endfunction()

# Returns the canonical configured git repository pins. File repositories are intentionally omitted.
function(_cdpm_lockfile_collect_git_repos out_repos)
    get_property(repo_json GLOBAL PROPERTY CDPM_REPO_JSON)
    set(result "[]")
    if(repo_json)
        string(JSON repos ERROR_VARIABLE repos_err GET "${repo_json}" repos)
        if(NOT repos_err)
            string(JSON repo_count LENGTH "${repos}")
            if(repo_count GREATER 0)
                math(EXPR repo_last "${repo_count} - 1")
                foreach(i RANGE 0 ${repo_last})
                    string(JSON repo GET "${repos}" ${i})
                    string(JSON kind ERROR_VARIABLE kind_err GET "${repo}" kind)
                    if(kind_err OR NOT kind STREQUAL "git")
                        continue()
                    endif()
                    string(JSON url ERROR_VARIABLE url_err GET "${repo}" url)
                    string(JSON baseline ERROR_VARIABLE baseline_err GET "${repo}" baseline)
                    if(url_err OR baseline_err)
                        continue()
                    endif()
                    set(pin "{}")
                    _cdpm_json_set_safe("${pin}" url "${url}" STRING pin)
                    _cdpm_json_set_safe("${pin}" baseline "${baseline}" STRING pin)
                    string(JSON result_length LENGTH "${result}")
                    string(JSON result SET "${result}" ${result_length} "${pin}")
                endforeach()
            endif()
        endif()
    endif()
    cdpm_canonical_json("${result}" result)
    set(${out_repos} "${result}")
    return(PROPAGATE ${out_repos})
endfunction()

# .. rst:
# ``cdpm_write_lockfile(<pkg_name> <version> <config_hash> <source_json> <dev>
#                      [DEPENDENCIES <json>] [SYSTEM_IDENTITIES <json>])``
#
# Records (or replaces) the ``<pkg_name>`` entry in the lockfile and persists the file. ``<source_json>`` is
# the normalized source object from :cmake:command:`cdpm_get_package_source` /
# :cmake:command:`cdpm_prepare_source`; the integrity fields are extracted from it by type:
#
# * ``git``   -> ``source_url`` + ``git_commit`` (from ``url`` / ``rev``);
# * ``url``   -> ``source_url`` + ``source_sha256`` (from ``url`` / ``sha256``);
# * ``local`` -> no integrity fields (a dev source is not reproducible).
#
# ``<dev>`` is stored verbatim as a JSON boolean. Optional identity maps are canonicalized. The file is
# rewritten atomically in canonical form (sorted keys) for clean VCS diffs. Loads the lockfile on demand.
function(cdpm_write_lockfile pkg_name version config_hash source_json dev)
    cmake_parse_arguments(arg "HOST" "DEPENDENCIES;HOST_DEPENDENCIES;SYSTEM_IDENTITIES" "" ${ARGN})
    _cdpm_lockfile_ensure_loaded()
    string(TOLOWER "${pkg_name}" name)
    set(compose_args "")
    if(DEFINED arg_DEPENDENCIES)
        list(APPEND compose_args DEPENDENCIES "${arg_DEPENDENCIES}")
    endif()
    if(DEFINED arg_SYSTEM_IDENTITIES)
        list(APPEND compose_args SYSTEM_IDENTITIES "${arg_SYSTEM_IDENTITIES}")
    endif()
    if(DEFINED arg_HOST_DEPENDENCIES)
        list(APPEND compose_args HOST_DEPENDENCIES "${arg_HOST_DEPENDENCIES}")
    endif()
    _cdpm_lockfile_compose_entry("${version}" "${config_hash}" "${source_json}" "${dev}" entry
        ${compose_args})
    set(entries "{}")
    string(JSON entries SET "${entries}" "${name}" "${entry}")
    if(arg_HOST)
        _cdpm_lockfile_commit_entries("{}" HOST_ENTRIES "${entries}")
    else()
        _cdpm_lockfile_commit_entries("${entries}")
    endif()
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
    _cdpm_lockfile_collect_git_repos(out_repos)

    get_property(lock GLOBAL PROPERTY CDPM_LOCKFILE_JSON)
    if(NOT lock)
        _cdpm_lockfile_skeleton(lock)
    endif()
    string(JSON lock SET "${lock}" repos "${out_repos}")
    cdpm_canonical_json("${lock}" lock)

    get_property(path GLOBAL PROPERTY CDPM_LOCKFILE_PATH)
    if(NOT path)
        _cdpm_lockfile_default_path(path)
    endif()
    _cdpm_lockfile_persist("${lock}")
endfunction()
