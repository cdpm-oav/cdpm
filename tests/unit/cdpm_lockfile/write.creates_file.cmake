# Test: write.creates_file
# A git source produces version/config_hash/source_url/git_commit, dev:false, no source_sha256.
include(cdpm_lockfile)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/write_creates_file")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(lock "${tmp}/cdpm.lock.json")

cdpm_read_lockfile(PATH "${lock}")

set(src "{}")
string(JSON src SET "${src}" "type" "\"git\"")
string(JSON src SET "${src}" "url" "\"https://github.com/fmtlib/fmt.git\"")
string(JSON src SET "${src}" "rev" "\"e69e5f977d458f2650bb346dadf2ad30c5320281\"")

cdpm_write_lockfile("fmt" "11.2.0" "a1b2c3d4e5f6a7b8" "${src}" FALSE)

set(lock_exists FALSE)
if(EXISTS "${lock}")
    set(lock_exists TRUE)
endif()
assert_true("${lock_exists}" "lockfile written to disk")

file(READ "${lock}" out)
string(JSON entry GET "${out}" "packages" "fmt")
assert_json_member("${entry}" "version" "11.2.0" "version recorded")
assert_json_member("${entry}" "config_hash" "a1b2c3d4e5f6a7b8" "config_hash recorded")
assert_json_member("${entry}" "source_url" "https://github.com/fmtlib/fmt.git" "source_url recorded")
assert_json_member("${entry}" "git_commit" "e69e5f977d458f2650bb346dadf2ad30c5320281" "git_commit recorded")
assert_json_member("${entry}" "dev" "OFF" "dev is false")

# url-only field must be absent for a git source.
string(JSON sha ERROR_VARIABLE sha_err GET "${entry}" "source_sha256")
assert_true(sha_err "source_sha256 absent for a git source")

# Top-level schema header.
assert_json_member("${out}" "lock_schema" "1" "lock_schema header")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: write.creates_file")
