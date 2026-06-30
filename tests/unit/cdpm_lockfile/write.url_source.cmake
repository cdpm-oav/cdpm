# Test: write.url_source
# A url source records source_url + source_sha256 and omits git_commit.
include(cdpm_lockfile)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/write_url_source")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(lock "${tmp}/cdpm.lock.json")

cdpm_read_lockfile(PATH "${lock}")

set(src "{}")
string(JSON src SET "${src}" "type" "\"url\"")
string(JSON src SET "${src}" "url" "\"https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz\"")
string(JSON src SET "${src}" "sha256" "\"9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23\"")

cdpm_write_lockfile("zlib" "1.3.1" "9f8e7d6c5b4a3210" "${src}" FALSE)

file(READ "${lock}" out)
string(JSON entry GET "${out}" "packages" "zlib")
assert_json_member("${entry}" "source_url"
    "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz" "source_url recorded")
assert_json_member("${entry}" "source_sha256"
    "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23" "source_sha256 recorded")

string(JSON gc ERROR_VARIABLE gc_err GET "${entry}" "git_commit")
assert_true(gc_err "git_commit absent for a url source")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: write.url_source")
