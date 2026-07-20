# cdpm_bs_openssl.cmake - OpenSSL build-system driver for cdpm (stub).

include_guard(GLOBAL)

# .. rst:
# ``cdpm_bs_openssl_build(<ctx_json>)``
#
# Driver for OpenSSL (perl Configure + make/nmake). Not yet implemented.
#
# Planned: run ``perl Configure <target> <opts> --prefix=<install_dir>`` where ``<target>`` is selected
# from the package's ``build.configure_target_map`` keyed by ``${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}``
# (e.g. ``linux-x86_64``, ``VC-WIN64A``, ``darwin64-arm64-cc``); options such as ``no-shared`` / ``no-tests``
# pass through verbatim. Build with ``make`` (Unix) or ``nmake`` (Windows, possibly with nasm). Tools are
# located via ``find_program``; all steps via ``execute_process``.
function(cdpm_bs_openssl_build ctx_json)
    _cdpm_cleanup_driver_user_file("${ctx_json}")
    message(FATAL_ERROR
        "[cdpm] build-system driver 'openssl' is not yet implemented. "
        "Only the 'cmake' driver is available in this version."
    )
endfunction()
