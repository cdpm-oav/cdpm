# cdpm_bs_autotools.cmake - Autotools build-system driver for cdpm (stub).

include_guard(GLOBAL)

# .. rst:
# ``cdpm_bs_autotools_build(<ctx_json>)``
#
# Driver for GNU Autotools packages (e.g. gmp, libxml2 on Unix). Not yet implemented.
#
# Planned: run ``<src_dir>/configure --prefix=<install_dir> <configure_args>`` (adding ``--host=<triplet>``
# derived from the toolchain when cross-compiling, mirroring vcpkg_configure_make's BUILD_TRIPLET), then
# ``make`` and ``make install`` via ``execute_process``. Options are passed through as native
# ``configure`` arguments (``configure_args`` list). All work through ``execute_process`` - no shell.
function(cdpm_bs_autotools_build ctx_json)
    message(FATAL_ERROR
        "[cdpm] build-system driver 'autotools' is not yet implemented. "
        "Only the 'cmake' driver is available in this version."
    )
endfunction()
