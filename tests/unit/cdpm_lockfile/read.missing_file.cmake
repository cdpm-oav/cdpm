# Test: read.missing_file
# A missing lockfile is not an error: the cache is seeded with the empty schema skeleton.
include(cdpm_lockfile)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/read_missing_file")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(lock "${tmp}/does_not_exist.json")

cdpm_read_lockfile(PATH "${lock}")

# No file should have been created by a read.
set(exists FALSE)
if(EXISTS "${lock}")
    set(exists TRUE)
endif()
assert_false("${exists}" "read does not create the file")

# Cache holds a valid skeleton with an empty packages object.
get_property(cached GLOBAL PROPERTY CDPM_LOCKFILE_JSON)
string(JSON pkgs_type TYPE "${cached}" "packages")
assert_eq("${pkgs_type}" "OBJECT" "skeleton has a packages object")
string(JSON n LENGTH "${cached}" "packages")
assert_eq("${n}" "0" "skeleton packages is empty")

# Lookup on the empty skeleton misses cleanly.
cdpm_lockfile_get("anything" found entry)
assert_false("${found}" "lookup misses on an empty lockfile")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: read.missing_file")
