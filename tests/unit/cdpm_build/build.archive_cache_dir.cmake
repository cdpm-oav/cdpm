# Test: build.archive_cache_dir
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/archive_cache_dir")
file(REMOVE_RECURSE "${tmp}")
set(CMAKE_BINARY_DIR "${tmp}/bin")
set(CDPM_CACHE_PATH "${tmp}/cache")

set(sha "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
set(url_source "{\"type\":\"url\",\"url\":\"https://example.com/archive.tar.gz\",\"sha256\":\"${sha}\"}")

_cdpm_resolve_archive_cache_dir("${url_source}" cache_dir)
assert_true("${cache_dir}" "URL source returns a non-empty cache dir")
assert_match("${cache_dir}" "\\.cdpm_archives/0123456789abcdef$" "cache dir contains the SHA-256 prefix")
assert_match("${cache_dir}" "^${CDPM_CACHE_PATH}" "cache dir lives under CDPM_CACHE_PATH")

set(git_source [[{"type":"git","url":"https://example.com/repo.git","rev":"deadbeefcafedeadbeefcafedeadbeefdeadbeef"}]])
_cdpm_resolve_archive_cache_dir("${git_source}" git_cache_dir)
assert_empty("${git_cache_dir}" "git source returns an empty cache dir")

set(local_source "{\"type\":\"local\",\"path\":\"${tmp}/src\"}")
_cdpm_resolve_archive_cache_dir("${local_source}" local_cache_dir)
assert_empty("${local_cache_dir}" "local source returns an empty cache dir")

set(url_no_sha "{\"type\":\"url\",\"url\":\"https://example.com/archive.tar.gz\"}")
_cdpm_resolve_archive_cache_dir("${url_no_sha}" no_sha_cache_dir)
assert_empty("${no_sha_cache_dir}" "URL source without SHA-256 returns an empty cache dir")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: _cdpm_resolve_archive_cache_dir")
