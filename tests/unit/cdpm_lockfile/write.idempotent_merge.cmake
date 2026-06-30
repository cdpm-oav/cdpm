# Test: write.idempotent_merge
# Multiple packages coexist; re-writing the same entry yields byte-identical canonical output.
include(cdpm_lockfile)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/write_idempotent_merge")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(lock "${tmp}/cdpm.lock.json")

cdpm_read_lockfile(PATH "${lock}")

set(git_src "{}")
string(JSON git_src SET "${git_src}" "type" "\"git\"")
string(JSON git_src SET "${git_src}" "url" "\"https://github.com/fmtlib/fmt.git\"")
string(JSON git_src SET "${git_src}" "rev" "\"abc123\"")

set(url_src "{}")
string(JSON url_src SET "${url_src}" "type" "\"url\"")
string(JSON url_src SET "${url_src}" "url" "\"https://example/zlib.tgz\"")
string(JSON url_src SET "${url_src}" "sha256" "\"deadbeef\"")

cdpm_write_lockfile("fmt" "11.2.0" "hashfmt0000000000" "${git_src}" FALSE)
cdpm_write_lockfile("zlib" "1.3.1" "hashzlib000000000" "${url_src}" FALSE)

file(READ "${lock}" first)

# Both packages present.
string(JSON nfmt ERROR_VARIABLE e1 GET "${first}" "packages" "fmt" "version")
string(JSON nzlib ERROR_VARIABLE e2 GET "${first}" "packages" "zlib" "version")
assert_eq("${nfmt}" "11.2.0" "fmt coexists")
assert_eq("${nzlib}" "1.3.1" "zlib coexists")

# Re-writing the identical fmt entry must not change the file.
cdpm_write_lockfile("fmt" "11.2.0" "hashfmt0000000000" "${git_src}" FALSE)
file(READ "${lock}" second)
assert_eq("${second}" "${first}" "re-writing the same entry is byte-stable")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: write.idempotent_merge")
