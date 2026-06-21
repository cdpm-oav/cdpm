# cdpm_version.cmake - Loads the cdpm version string from the `VERSION` file.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# Resolve cdpm root (parent of core/) so the module works regardless of who included it; 
# stored in a temporary local variable cleaned up at end of file.
cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH __cdpm_version_module_root)

# Test/embedder override hook: when ``__CDPM_VERSION_FILE`` is set BEFORE this module is included, 
# that path is read instead of the default ``<root>/VERSION``.
# Used by ``tests/unit/cdpm_version/**`` to inject fixture files.
if(NOT DEFINED __CDPM_VERSION_FILE OR __CDPM_VERSION_FILE STREQUAL "")
    set(__CDPM_VERSION_FILE "${__cdpm_version_module_root}/VERSION")
endif()

# .. rst:
# Loads the version string at include time and caches it in the INTERNAL cache variable ``__CDPM_VERSION_CACHED``. 
# Subsequent includes are no-ops thanks to ``include_guard(GLOBAL)``, and the cache survives across function scopes.
#
# Validation strategy (warnings only, never fatal -- the CLI banner and the ``version`` command must work 
# even on a half-broken checkout):
#
# - Missing file       -> WARNING + fallback ``"0.0.0-unknown"``
# - Empty file         -> WARNING + fallback ``"0.0.0-unknown"``
# - Non-semver content -> WARNING, value used as-is
#
# Semver regex is ``MAJOR.MINOR.PATCH(-PRERELEASE|+BUILD)?`` 
# (subset of semver.org 2.0.0 sufficient for cdpm's release scheme).
if(NOT DEFINED __CDPM_VERSION_CACHED)
    block(PROPAGATE __CDPM_VERSION_CACHED)
        set(__cdpm_version_fallback "0.0.0-unknown")

        if(EXISTS "${__CDPM_VERSION_FILE}")
            file(READ "${__CDPM_VERSION_FILE}" __cdpm_version_raw)
            string(STRIP "${__cdpm_version_raw}" __cdpm_version_raw)

            if(__cdpm_version_raw STREQUAL "")
                message(WARNING
                    "[cdpm] VERSION file is empty: ${__CDPM_VERSION_FILE} "
                    "-- falling back to '${__cdpm_version_fallback}'")
                set(__cdpm_version_raw "${__cdpm_version_fallback}")
            elseif(NOT __cdpm_version_raw MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+([-+].+)?$")
                # Non-semver content is preserved verbatim; only a diagnostic is emitted.
                message(WARNING
                    "[cdpm] VERSION file content does not look like semver: "
                    "'${__cdpm_version_raw}' (${__CDPM_VERSION_FILE})")
            endif()
        else()
            message(WARNING
                "[cdpm] VERSION file not found: ${__CDPM_VERSION_FILE} "
                "-- falling back to '${__cdpm_version_fallback}'")
            set(__cdpm_version_raw "${__cdpm_version_fallback}")
        endif()

        set(__CDPM_VERSION_CACHED "${__cdpm_version_raw}"
            CACHE INTERNAL "cdpm version string (loaded from VERSION file)" FORCE)
    endblock()
endif()

# Drop the local helper; module-private __CDPM_VERSION_* survive.
unset(__cdpm_version_module_root)

# .. rst:
# ``_cdpm_get_version(<out_var>)``
#
# Returns the cdpm version string loaded from the VERSION file at module include time. 
# The value is identical for the lifetime of the configure run (cached in ``__CDPM_VERSION_CACHED``); 
# repeated calls do not re-read the file. Module-private by the cdpm underscore convention; 
# consumed by the CLI ``help`` and ``version`` commands.
function(_cdpm_get_version out_var)
    set(${out_var} "${__CDPM_VERSION_CACHED}")
    return(PROPAGATE ${out_var})
endfunction()
