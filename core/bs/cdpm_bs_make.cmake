# cdpm_bs_make.cmake - Make/NMake build-system driver for cdpm (stub).

include_guard(GLOBAL)

# .. rst:
# ``cdpm_bs_make_build(<ctx_json>)``
#
# Driver for plain Makefile / NMake projects. Not yet implemented.
#
# Planned: locate the make tool (``make`` / ``nmake`` / ``mingw32-make``) via ``find_program``, then run
# the declared ``targets`` against the package ``makefile``, forwarding ``defines`` as ``KEY=VAL`` make
# variables. On Windows + NMake the driver must enter the Visual Studio environment (vcvarsall via
# vswhere) - the single, isolated place where a platform-specific shell call is permitted.
function(cdpm_bs_make_build ctx_json)
    _cdpm_cleanup_driver_user_file("${ctx_json}")
    message(FATAL_ERROR
        "[cdpm] build-system driver 'make' is not yet implemented. "
        "Only the 'cmake' driver is available in this version."
    )
endfunction()
