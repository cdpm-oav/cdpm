# cdpm_bs_b2.cmake - Boost.Build (b2) build-system driver for cdpm (stub).

include_guard(GLOBAL)

# .. rst:
# ``cdpm_bs_b2_build(<ctx_json>)``
#
# Driver for Boost (Boost.Build / b2). Not yet implemented.
#
# Planned: bootstrap b2 from the Boost source tree (``bootstrap``), then translate the CMake context into
# b2 terms: ``toolset=`` from ``CMAKE_CXX_COMPILER_ID``, ``address-model=`` from ``CMAKE_SIZEOF_VOID_P``,
# ``variant=`` from ``CMAKE_BUILD_TYPE``, ``link=static|shared``, and ``--with-<lib>`` from a
# ``libraries`` option list (the BoostBuild.cmake pattern used by vcpkg). All via ``execute_process``.
function(cdpm_bs_b2_build ctx_json)
    _cdpm_cleanup_driver_user_file("${ctx_json}")
    message(FATAL_ERROR
        "[cdpm] build-system driver 'b2' is not yet implemented. "
        "Only the 'cmake' driver is available in this version."
    )
endfunction()
