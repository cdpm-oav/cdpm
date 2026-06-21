# Test: get_package_source.repo_default
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# With no source_override, the resolved source is the repo source with the
# version's integrity pin folded in (git -> rev); dev=FALSE.
set(meta [[{"source":{"type":"git","url":"https://example/fmt.git"},
"versions":{"1.2.3":{"rev":"deadbeefcafedeadbeefcafedeadbeefdeadbeef"}}}]])

cdpm_get_package_source("fmt" "${meta}" "1.2.3" src dev)

assert_false("${dev}" "no override means not a dev build")
assert_json_member("${src}" "type" "git" "source type preserved")
assert_json_member("${src}" "rev"  "deadbeefcafedeadbeefcafedeadbeefdeadbeef" "version rev folded into source")

message(STATUS "PASS: get_package_source returns repo source + version pin")
