# Test: build.b2_user_config_jam
#
# Verifies _cdpm_b2_user_config_jam writes a user-config.jam only when a toolchain
# file is present and returns the correct path/needed indicators.

include(bs/cdpm_bs_b2)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(build_dir "${CMAKE_CURRENT_LIST_DIR}/.tmp/user_config_jam")
file(REMOVE_RECURSE "${build_dir}")
file(MAKE_DIRECTORY "${build_dir}")

# ---------------------------------------------------------------------------
# Without a toolchain, no file should be generated.
# ---------------------------------------------------------------------------
set(ctx_json "{\"build_dir\":\"${build_dir}\"}")
_cdpm_b2_user_config_jam("${ctx_json}" jam_path needed)
assert_empty("${jam_path}" "jam_path without toolchain")
assert_false("${needed}" "needed without toolchain")

# ---------------------------------------------------------------------------
# With a toolchain, user-config.jam should be generated for the selected toolset.
# ---------------------------------------------------------------------------
set(CMAKE_CXX_COMPILER_ID "GNU")
set(CMAKE_CXX_COMPILER "/usr/bin/g++")
set(ctx_json "{\"build_dir\":\"${build_dir}\",\"toolchain\":\"/fake/toolchain.cmake\"}")

_cdpm_b2_user_config_jam("${ctx_json}" jam_path needed)

assert_eq("${jam_path}" "${build_dir}/user-config.jam" "jam_path with toolchain")
assert_true("${needed}" "needed with toolchain")

file(READ "${jam_path}" jam_content)
assert_eq("${jam_content}" "using gcc : : /usr/bin/g++ ;\n" "user-config.jam content")

file(REMOVE_RECURSE "${build_dir}")

message(STATUS "PASS: build.b2_user_config_jam")
