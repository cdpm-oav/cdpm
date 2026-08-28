include(cdpm_orchestrator)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/env_key")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

file(WRITE "${tmp}/tc_a.cmake" "# toolchain a\n")
file(WRITE "${tmp}/tc_b.cmake" "# toolchain b\n")

_cdpm_orchestrator_env_key("Unix Makefiles" "Release" "${tmp}/tc_a.cmake" key1)
_cdpm_orchestrator_env_key("Unix Makefiles" "Release" "${tmp}/tc_a.cmake" key2)
assert_eq("${key1}" "${key2}" "same inputs produce the same env-key")
assert_match("${key1}" "^[0-9a-fA-F]+$" "env-key is hexadecimal")
string(LENGTH "${key1}" key_len)
assert_eq("${key_len}" "16" "env-key length is 16")

_cdpm_orchestrator_env_key("Ninja" "Release" "${tmp}/tc_a.cmake" key_gen)
assert_ne("${key_gen}" "${key1}" "different generator changes env-key")

_cdpm_orchestrator_env_key("Unix Makefiles" "Debug" "${tmp}/tc_a.cmake" key_cfg)
assert_ne("${key_cfg}" "${key1}" "different build type changes env-key")

_cdpm_orchestrator_env_key("Unix Makefiles" "Release" "${tmp}/tc_b.cmake" key_tc)
assert_ne("${key_tc}" "${key1}" "different toolchain content changes env-key")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: orchestrator env-key is deterministic and environment-sensitive")
