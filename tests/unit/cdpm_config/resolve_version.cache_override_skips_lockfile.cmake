include("${CDPM_TEST_HELPERS}/helpers.cmake")
include(cdpm_config)
include(cdpm_lockfile)

set(meta [[{
    "default_version": "2.0.0",
    "versions": {
        "1.0.0": { "compat_version": "1.0.0" },
        "2.0.0": { "compat_version": "2.0.0" },
        "3.0.0": { "compat_version": "3.0.0" }
    }
}]])

# Seed a lockfile that pins an older version.
set(lock [=[{
    "cdpm_version": "0.0.1",
    "lock_schema": 1,
    "packages": {
        "demo": {
            "version": "1.0.0",
            "config_hash": "aaaaaaaaaaaaaaaa",
            "dependencies": {},
            "dev": false
        }
    },
    "repos": []
}]=])
set_property(GLOBAL PROPERTY CDPM_LOCKFILE_JSON "${lock}")
set_property(GLOBAL PROPERTY CDPM_LOCKFILE_LOADED TRUE)

# A CDPM_<PKG>_VERSION cache variable must override the lockfile pin.
set(CDPM_DEMO_VERSION "3.0.0" CACHE STRING "demo version override" FORCE)

cdpm_resolve_version("demo" "${meta}" "" version compat)
assert_eq("${version}" "3.0.0" "CDPM_DEMO_VERSION should override lockfile pin")
assert_eq("${compat}" "3.0.0" "compat_version should come from the selected version")

message(STATUS "PASS")
