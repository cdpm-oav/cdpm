# Contains `cdpm_provide_dependency` macro for external dependency management support

include_guard(GLOBAL)

macro(cdpm_provide_dependency method_type)
    # TODO: implementation
    find_package(${ARGN} BYPASS_PROVIDER)
endmacro()
