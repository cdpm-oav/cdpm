include("${CDPM_TEST_HELPERS}/helpers.cmake")
include(cdpm_config)

set(meta [[{
    "default_version": "11.2.0",
    "versions": {
        "12.0.0": {"compat_version": "12.0.0"},
        "11.2.0": {"compat_version": "11.0.0"},
        "12.2.0": {"compat_version": "12.0.0"},
        "11.3.0": {"compat_version": "11.0.0"},
        "12.1.0": {"compat_version": "12.0.0"}
    }
}]])

cdpm_resolve_version(demo "${meta}" "12" version compat)
assert_eq("${version}" "12.2.0" "highest compatible version despite registry order")
assert_eq("${compat}" "12.0.0" "compatibility of chosen version")
foreach(request IN ITEMS 11 11.1)
    cdpm_resolve_version(demo "${meta}" "${request}" version compat)
    assert_eq("${version}" "11.2.0" "keep compatible default for ${request}")
endforeach()
cdpm_resolve_version(demo "${meta}" "12.1.0" version compat EXACT)
assert_eq("${version}" "12.1.0" "EXACT selects the matching non-default version")
cdpm_resolve_version(demo "${meta}" "" version compat)
assert_eq("${version}" "11.2.0" "no request keeps default")

set(no_default [[{"versions":{"1.0.0":{},"2.0.0":{"compat_version":"2.0.0"}}}]])
cdpm_resolve_version(demo "${no_default}" "2" version compat)
assert_eq("${version}" "2.0.0" "request selects version without a default")
