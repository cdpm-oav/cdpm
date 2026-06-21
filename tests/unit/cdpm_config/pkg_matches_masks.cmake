# Test: pkg_matches_masks
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Ownership masks: empty array owns everything; exact and prefix ('*') masks.

# Empty masks -> owns every package.
_cdpm_pkg_matches_masks("anything" "[]" ok)
assert_true("${ok}" "empty masks own everything")

# Exact match.
_cdpm_pkg_matches_masks("openssl" [=[["openssl"]]=] ok)
assert_true("${ok}" "exact mask matches")

# Exact mask must not match a different name.
_cdpm_pkg_matches_masks("openssl-extra" [=[["openssl"]]=] ok)
assert_false("${ok}" "exact mask does not match a different name")

# Prefix mask ('boost-*') matches by prefix.
_cdpm_pkg_matches_masks("boost-system" [=[["boost-*"]]=] ok)
assert_true("${ok}" "prefix mask matches by prefix")

# Prefix mask does not match an unrelated name.
_cdpm_pkg_matches_masks("zlib" [=[["boost-*"]]=] ok)
assert_false("${ok}" "prefix mask does not match unrelated name")

# Multiple masks: a hit on any mask is enough.
_cdpm_pkg_matches_masks("openssl" [=[["boost-*","openssl"]]=] ok)
assert_true("${ok}" "any matching mask qualifies")

message(STATUS "PASS: _cdpm_pkg_matches_masks honours empty/exact/prefix masks")
