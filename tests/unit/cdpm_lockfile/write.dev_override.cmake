# Test: write.dev_override
# A local (dev) source records dev:true and no integrity fields (not reproducible).
include(cdpm_lockfile)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/write_dev_override")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(lock "${tmp}/cdpm.lock.json")

cdpm_read_lockfile(PATH "${lock}")

set(src "{}")
string(JSON src SET "${src}" "type" "\"local\"")
string(JSON src SET "${src}" "path" "\"/work/mylib\"")

cdpm_write_lockfile("mylib" "0.0.0-dev" "f0e1d2c3b4a59687" "${src}" TRUE)

file(READ "${lock}" out)
string(JSON entry GET "${out}" "packages" "mylib")
assert_json_member("${entry}" "dev" "ON" "dev is true")

foreach(field source_url git_commit source_sha256)
    string(JSON v ERROR_VARIABLE v_err GET "${entry}" "${field}")
    assert_true(v_err "${field} absent for a dev/local source")
endforeach()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: write.dev_override")
