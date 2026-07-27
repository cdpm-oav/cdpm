# Test: build.b2_variant_mapping
#
# Verifies _cdpm_b2_variant maps CMAKE_BUILD_TYPE to the correct b2 variant value.

include(bs/cdpm_bs_b2)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

function(test_variant build_type expected_variant)
    set(CMAKE_BUILD_TYPE "${build_type}")
    _cdpm_b2_variant("{}" variant)
    assert_eq("${variant}" "${expected_variant}" "_cdpm_b2_variant for '${build_type}'")
endfunction()

test_variant("Debug" "debug")
test_variant("Release" "release")
test_variant("RelWithDebInfo" "release")
test_variant("MinSizeRel" "release")

# Empty build type means the variant is omitted entirely.
set(CMAKE_BUILD_TYPE "")
_cdpm_b2_variant("{}" variant)
assert_eq("${variant}" "" "_cdpm_b2_variant for empty build type")

message(STATUS "PASS: build.b2_variant_mapping")
