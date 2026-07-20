include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/validate_api")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/valid/demo" "${tmp}/malformed/good" "${tmp}/malformed/bad" "${tmp}/unsafe")
set(manifest [[{"source":{"type":"git","url":"https://example.test/demo.git"},
"versions":{"1":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}]])
file(WRITE "${tmp}/valid/demo/package.json" "${manifest}")
file(WRITE "${tmp}/valid/packages.json" [[{"repo_schema":2,"packages":{"demo":"demo/package.json"}}]])
file(SHA256 "${tmp}/valid/packages.json" before_index)
file(SHA256 "${tmp}/valid/demo/package.json" before_manifest)

cdpm_validate_registry("${tmp}/valid" valid_dir diagnostics)
assert_true("${valid_dir}" "directory path form validates")
cdpm_validate_registry("${tmp}/valid/packages.json" valid_file diagnostics)
assert_true("${valid_file}" "packages.json path form validates")
file(SHA256 "${tmp}/valid/packages.json" after_index)
file(SHA256 "${tmp}/valid/demo/package.json" after_manifest)
assert_eq("${after_index}" "${before_index}" "validation does not mutate the index")
assert_eq("${after_manifest}" "${before_manifest}" "validation does not mutate manifests")

file(WRITE "${tmp}/malformed/good/package.json" "${manifest}")
file(WRITE "${tmp}/malformed/bad/package.json" "not-json")
file(WRITE "${tmp}/malformed/packages.json"
    [[{"repo_schema":2,"packages":{"good":"good/package.json","bad":"bad/package.json"}}]])
cdpm_validate_registry("${tmp}/malformed" malformed_valid diagnostics)
assert_false("${malformed_valid}" "full validation catches an unrelated malformed manifest")
assert_match("${diagnostics}" "package 'bad'.*not a JSON object" "malformed manifest diagnostic identifies canonical key")

file(WRITE "${tmp}/unsafe/packages.json" [[{"repo_schema":2,"packages":{"demo":"../outside.json"}}]])
cdpm_validate_registry("${tmp}/unsafe" unsafe_valid diagnostics)
assert_false("${unsafe_valid}" "full validation catches an unsafe manifest path")
assert_match("${diagnostics}" "must not contain '\.\.'" "unsafe path diagnostic is clear")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: public full-registry validation is read-only and accepts both path forms")
