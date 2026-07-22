# Test: load_repos.file_and_masks
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# cdpm_load_repos walks CDPM_REPO_JSON repos[] (kind=file) and forwards each
# repo's `packages` masks to cdpm_load_repo: only matching names are registered.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/load_repos_masks")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

# A repo file with two packages; the mask only owns 'fmt'.
file(MAKE_DIRECTORY "${tmp}/packages/fmt" "${tmp}/packages/zlib")
file(WRITE "${tmp}/packages/fmt/package.json"
[[{"source":{"type":"git","url":"https://example/fmt.git"},
"versions":{"1.0.0":{"rev":"deadbeefcafedeadbeefcafedeadbeefdeadbeef"}}}]])
file(WRITE "${tmp}/packages/zlib/package.json"
[[{"source":{"type":"git","url":"https://example/zlib.git"},
"versions":{"1.0.0":{"rev":"cafedeadbeefcafedeadbeefcafedeadbeefcafe"}}}]])
file(WRITE "${tmp}/packages.json"
[[{"version":1,"packages":{
"fmt":"packages/fmt/package.json",
"zlib":"packages/zlib/package.json"}}]])

# Project config declaring the file repo with a 'fmt' ownership mask.
file(WRITE "${tmp}/cdpm.json"
"{\"cdpm_schema\":1,\"repos\":[{\"kind\":\"file\",\"path\":\"${tmp}/packages.json\",\"packages\":[\"fmt\"]}]}")

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "")
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "")
cdpm_config_load(FORCE)
cdpm_load_repos()

cdpm_find_in_repo("fmt" found_fmt meta_fmt)
assert_true("${found_fmt}" "masked-in package 'fmt' is registered")

cdpm_find_in_repo("zlib" found_zlib meta_zlib)
assert_false("${found_zlib}" "masked-out package 'zlib' is not registered")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm_load_repos loads kind=file repos and applies masks")
