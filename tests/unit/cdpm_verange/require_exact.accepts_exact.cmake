# Test: require_exact.accepts_exact
include(cdpm_verange)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Numeric exact versions are returned unchanged.
_cdpm_require_exact_version("foo" "test" "1.2.3" v)
assert_eq("${v}" "1.2.3" "dotted numeric version is exact")

_cdpm_require_exact_version("foo" "test" "9.1.0" v)
assert_eq("${v}" "9.1.0" "another dotted numeric version is exact")

_cdpm_require_exact_version("foo" "test" "1" v)
assert_eq("${v}" "1" "single-digit version is exact")

# Pre-release/build-metadata suffixes are accepted as plain exact tokens (legacy behavior).
_cdpm_require_exact_version("foo" "test" "1.2.3-beta" v)
assert_eq("${v}" "1.2.3-beta" "pre-release suffix is accepted as an exact version")

_cdpm_require_exact_version("foo" "test" "1.2.3+build" v)
assert_eq("${v}" "1.2.3+build" "build metadata suffix is accepted as an exact version")

# Non-version tokens are treated as an absent constraint.
_cdpm_require_exact_version("foo" "test" "CONFIG" v)
assert_eq("${v}" "" "CMake keyword yields empty constraint")

# Empty input yields empty output.
_cdpm_require_exact_version("foo" "test" "" v)
assert_eq("${v}" "" "empty spec yields empty constraint")

message(STATUS "PASS: _cdpm_require_exact_version accepts exact requests")
