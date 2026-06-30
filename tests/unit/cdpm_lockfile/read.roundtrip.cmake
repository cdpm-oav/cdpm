# Test: read.roundtrip
# write -> fresh read -> cdpm_lockfile_get returns the recorded entry.
include(cdpm_lockfile)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/read_roundtrip")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(lock "${tmp}/cdpm.lock.json")

cdpm_read_lockfile(PATH "${lock}")

set(src "{}")
string(JSON src SET "${src}" "type" "\"git\"")
string(JSON src SET "${src}" "url" "\"https://example/fmt.git\"")
string(JSON src SET "${src}" "rev" "\"cafef00d\"")
cdpm_write_lockfile("fmt" "11.2.0" "deadbeefdeadbeef" "${src}" FALSE)

# Drop the cache and read again from disk.
set_property(GLOBAL PROPERTY CDPM_LOCKFILE_LOADED FALSE)
cdpm_read_lockfile(PATH "${lock}")

cdpm_lockfile_get("fmt" found entry)
assert_true("${found}" "fmt found after a fresh read")
assert_json_member("${entry}" "version" "11.2.0" "version survives the roundtrip")
assert_json_member("${entry}" "config_hash" "deadbeefdeadbeef" "config_hash survives the roundtrip")

# Case-insensitive lookup (key is lower-cased on write and on get).
cdpm_lockfile_get("FMT" found_uc entry_uc)
assert_true("${found_uc}" "lookup is case-insensitive")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: read.roundtrip")
