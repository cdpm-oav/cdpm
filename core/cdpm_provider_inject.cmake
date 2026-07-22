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
