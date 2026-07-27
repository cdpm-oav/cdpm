# Test: build.b2_toolset_unknown
#
# Verifies _cdpm_b2_toolset raises a fatal error when the compiler id is unknown
# and no build.toolset metadata is provided.

include(bs/cdpm_bs_b2)

set(CMAKE_CXX_COMPILER_ID "UnknownCompiler")
set(ctx_json "{}")

_cdpm_b2_toolset("${ctx_json}" toolset)

message(FATAL_ERROR "FAIL: expected _cdpm_b2_toolset to raise a fatal error")
