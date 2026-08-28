# Test: prepare.semantic_marker
include(cdpm_toolchain)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/semantic_marker")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(CMAKE_BINARY_DIR "${tmp}")

# Empty or missing toolchain path -> empty semantic id.
_cdpm_toolchain_semantic_id("" "" empty_id)
assert_eq("${empty_id}" "" "empty toolchain path gives empty semantic id")

set(real1 "${tmp}/real1.cmake")
file(WRITE "${real1}" "set(REAL_VALUE one)\n")

# Deterministic for identical inputs.
_cdpm_toolchain_semantic_id("${real1}" "" id1)
_cdpm_toolchain_semantic_id("${real1}" "" id2)
assert_eq("${id1}" "${id2}" "semantic id is deterministic")
string(LENGTH "${id1}" id_len)
assert_eq("${id_len}" "16" "semantic id is 16 chars")
assert_match("${id1}" "^[0-9a-f]+$" "semantic id is lower-case hex")

# Content change moves the id.
file(WRITE "${real1}" "set(REAL_VALUE two)\n")
_cdpm_toolchain_semantic_id("${real1}" "" id3)
assert_ne("${id1}" "${id3}" "changing toolchain content changes semantic id")

# Frozen allow-list value participates.
set(MY_FROZEN_VAR "frozen-value")
_cdpm_toolchain_semantic_id("${real1}" "MY_FROZEN_VAR" id4)
assert_ne("${id3}" "${id4}" "adding a frozen value changes semantic id")

# The generated wrapper stamps the marker for a real toolchain (16-hex id).
set(CMAKE_TOOLCHAIN_FILE "${real1}")
cdpm_prepare_toolchain("abc123" wrapper)
file(READ "${wrapper}" content)
assert_match("${content}" "set\\(CDPM_TOOLCHAIN_SEMANTIC_ID \"[0-9a-f]+\" CACHE INTERNAL" "wrapper stamps semantic marker")

# A native build (no external toolchain) stamps the non-empty sentinel instead of an
# empty value: empty cache values are fragile as presence signals in nested contexts.
unset(CMAKE_TOOLCHAIN_FILE)
unset(CDPM_TOOLCHAIN_SEMANTIC_ID)
cdpm_prepare_toolchain("nat123" native_wrapper)
file(READ "${native_wrapper}" native_content)
assert_match("${native_content}"
    "set\\(CDPM_TOOLCHAIN_SEMANTIC_ID \"native\" CACHE INTERNAL"
    "native build stamps the sentinel marker")

# A defined non-empty marker (real id or sentinel) propagates verbatim from the parent
# context; it is not recomputed from CMAKE_TOOLCHAIN_FILE, which points at the parent's
# cdpm wrapper there.
set(CDPM_TOOLCHAIN_SEMANTIC_ID "abc123def4567890")
set(CMAKE_TOOLCHAIN_FILE "${real1}")
cdpm_prepare_toolchain("prop123" propagated_wrapper)
file(READ "${propagated_wrapper}" propagated_content)
assert_match("${propagated_content}"
    "set\\(CDPM_TOOLCHAIN_SEMANTIC_ID \"abc123def4567890\" CACHE INTERNAL"
    "existing non-empty marker propagates without recomputation")

# The sentinel itself propagates the same way.
set(CDPM_TOOLCHAIN_SEMANTIC_ID "native")
cdpm_prepare_toolchain("prop456" sentinel_wrapper)
file(READ "${sentinel_wrapper}" sentinel_content)
assert_match("${sentinel_content}"
    "set\\(CDPM_TOOLCHAIN_SEMANTIC_ID \"native\" CACHE INTERNAL"
    "sentinel marker propagates without recomputation")

# A legacy empty marker (wrappers from older cdpm versions) is re-derived: with no
# external toolchain the sentinel is stamped, never an empty value.
set(CDPM_TOOLCHAIN_SEMANTIC_ID "")
unset(CMAKE_TOOLCHAIN_FILE)
cdpm_prepare_toolchain("lega123" legacy_wrapper)
file(READ "${legacy_wrapper}" legacy_content)
assert_match("${legacy_content}"
    "set\\(CDPM_TOOLCHAIN_SEMANTIC_ID \"native\" CACHE INTERNAL"
    "legacy empty marker is re-derived to the sentinel for a native build")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: toolchain semantic marker")
