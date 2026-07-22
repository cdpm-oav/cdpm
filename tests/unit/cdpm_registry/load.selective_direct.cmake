include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/selective_direct")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/packages/good" "${tmp}/packages/bad")
file(WRITE "${tmp}/packages/good/package.json" [[{"source":{"type":"git","url":"https://example.test/good.git"},
"versions":{"1":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}]])
file(WRITE "${tmp}/packages/bad/package.json" "not-json")
file(WRITE "${tmp}/packages.json"
    [[{"version":1,"packages":{"bad":"packages/bad/package.json","good":"packages/good/package.json"}}]])

cdpm_load_repo("${tmp}/packages.json")
cdpm_find_in_repo(good found meta)
assert_true("${found}" "exact canonical lookup succeeds without reading an unrelated malformed manifest")
string(JSON url GET "${meta}" source url)
assert_eq("${url}" "https://example.test/good.git" "exact lookup returns the selected manifest")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: manifest-index exact lookup reads only the selected manifest")
