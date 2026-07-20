# cdpm_bs_custom.cmake - Custom build-script driver for cdpm (stub).

include_guard(GLOBAL)

# .. rst:
# ``cdpm_bs_custom_build(<ctx_json>)``
#
# Driver for packages built by a user-provided build script (e.g. mpir under MSVC). Not yet implemented.
#
# Planned: ``include()`` the package's ``build_script`` (only honoured from committing config layers, per
# the layer-security rules) with the same lifecycle contract as a built-in driver - the script receives
# ``CDPM_PKG_NAME``, ``CDPM_PKG_VERSION``, ``CDPM_PKG_SOURCE_DIR``, ``CDPM_PKG_INSTALL_DIR``,
# ``CDPM_PKG_OPTIONS_JSON`` and the ``CDPM_USER_*`` variables, and performs configure/build/install
# through ``execute_process``.
function(cdpm_bs_custom_build ctx_json)
    _cdpm_cleanup_driver_user_file("${ctx_json}")
    message(FATAL_ERROR
        "[cdpm] build-system driver 'custom' is not yet implemented. "
        "Only the 'cmake' driver is available in this version."
    )
endfunction()
