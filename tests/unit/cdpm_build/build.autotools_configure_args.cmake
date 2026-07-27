# Test: build.autotools_configure_args
#
# Verifies _cdpm_autotools_configure_args translates the options object into
# autotools configure arguments:
#   boolean true   -> --enable-<key>
#   boolean false  -> --disable-<key>
#   non-empty str  -> --with-<key>=<val>
#   empty str      -> --without-<key>
#   key starts --  -> passed through verbatim (the key IS the flag, value ignored)

include(bs/cdpm_bs_autotools)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Build ctx_json with diverse option types.
set(ctx_json [[{"options":{"shared":true,"static":false,"prefix":"/usr/local","ssl":"","--with-custom-flag":"value"}}]])

# Call the function under test.
_cdpm_autotools_configure_args("${ctx_json}" result)

# Verify each expected argument is present in the result list.
foreach(_item IN ITEMS "--enable-shared" "--disable-static" "--with-prefix=/usr/local" "--without-ssl" "--with-custom-flag")
    list(FIND result "${_item}" _found)
    if(_found EQUAL -1)
        message(FATAL_ERROR "FAIL: expected '${_item}' in result\n  result: ${result}")
    endif()
endforeach()

message(STATUS "PASS: build.autotools_configure_args")
