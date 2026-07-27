# Test: build.b2_toolset_mapping
#
# Verifies _cdpm_b2_toolset maps CMAKE_CXX_COMPILER_ID to the correct b2 toolset name
# and falls back to build.toolset metadata when the compiler id is unknown.

include(bs/cdpm_bs_b2)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

function(test_toolset compiler_id expected_toolset)
    set(ctx_json "{}")
    if(ARGC GREATER 2)
        set(ctx_json "{\"build\":{\"toolset\":\"${ARGV2}\"}}")
    endif()

    set(CMAKE_CXX_COMPILER_ID "${compiler_id}")
    _cdpm_b2_toolset("${ctx_json}" toolset)
    assert_eq("${toolset}" "${expected_toolset}" "_cdpm_b2_toolset for ${compiler_id}")
endfunction()

test_toolset("GNU" "gcc")
test_toolset("Clang" "clang")
test_toolset("AppleClang" "clang")
test_toolset("MSVC" "msvc")
test_toolset("Intel" "intel")
test_toolset("IntelLLVM" "intel")
test_toolset("SunPro" "custom" "custom")

message(STATUS "PASS: build.b2_toolset_mapping")
