# Test: build.b2_address_model
#
# Verifies _cdpm_b2_address_model returns 32 or 64 based on CMAKE_SIZEOF_VOID_P.

include(bs/cdpm_bs_b2)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

function(test_address_model sizeof_void_p expected)
    set(CMAKE_SIZEOF_VOID_P "${sizeof_void_p}")
    _cdpm_b2_address_model("{}" am)
    assert_eq("${am}" "${expected}" "_cdpm_b2_address_model for sizeof_void_p=${sizeof_void_p}")
endfunction()

test_address_model("8" "64")
test_address_model("4" "32")

message(STATUS "PASS: build.b2_address_model")
