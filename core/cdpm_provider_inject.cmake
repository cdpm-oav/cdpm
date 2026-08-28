#.rst:
# cdpm_provider_inject
# --------------------
# Re-injects the cdpm dependency provider into ExternalProject child builds.
# Included via ``CMAKE_PROJECT_TOP_LEVEL_INCLUDES``; the cmake build driver
# forwards ``CDPM_INJECT_ROOT`` as a cache variable pointing at the cdpm tree.
include_guard(GLOBAL)

if(NOT DEFINED CDPM_INJECT_ROOT)
    return()
endif()

if(NOT EXISTS "${CDPM_INJECT_ROOT}/cdpm.cmake")
    message(FATAL_ERROR "[cdpm] CDPM_INJECT_ROOT does not contain cdpm.cmake: ${CDPM_INJECT_ROOT}")
endif()

# The child build inherits CMAKE_PREFIX_PATH from the parent, so already-built
# dependencies are findable without the provider.  The provider adds the ability
# to resolve and build packages on-demand that are NOT yet in the prefix path.
include("${CDPM_INJECT_ROOT}/cdpm.cmake")

# Nested resolves must see the same lockfile as the orchestrator so the nested
# UPDATE hash canary can compare against top-level entries.  When the build driver
# forwarded an explicit CDPM_LOCKFILE_PATH, read that file eagerly (the same
# pattern the orchestrator uses); otherwise the default path resolution applies.
if(DEFINED CDPM_LOCKFILE_PATH AND NOT CDPM_LOCKFILE_PATH STREQUAL "")
    cdpm_read_lockfile(PATH "${CDPM_LOCKFILE_PATH}")
endif()

# Mark nested resolver contexts so lockfile commits and canaries behave correctly.
set_property(GLOBAL PROPERTY __CDPM_RESOLVER_NESTED TRUE)

