# Test: read.bad_json (WILL_FAIL)
# A malformed lockfile is fatal.
include(cdpm_lockfile)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/read_bad_json")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(lock "${tmp}/cdpm.lock.json")

# Not a JSON object.
file(WRITE "${lock}" "this is not json {")

cdpm_read_lockfile(PATH "${lock}")

# Unreachable: the read above must abort.
message(STATUS "PASS: read.bad_json (unexpected -- should have failed)")
