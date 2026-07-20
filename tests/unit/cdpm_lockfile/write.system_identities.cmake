# Test: write.system_identities
include(cdpm_lockfile)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/write_system_identities")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(lock "${tmp}/cdpm.lock.json")
cdpm_read_lockfile(PATH "${lock}")

cdpm_write_lockfile(legacy 1 abc "{}" FALSE)
cdpm_write_lockfile(modern 2 def "{}" FALSE SYSTEM_IDENTITIES [[{"Foo":{"b":2,"a":1}}]])

file(READ "${lock}" content)
string(JSON legacy_system ERROR_VARIABLE legacy_err GET "${content}" packages legacy system_dependencies)
if(NOT legacy_err)
    message(FATAL_ERROR "FAIL: legacy call unexpectedly wrote system_dependencies")
endif()
string(JSON modern_system GET "${content}" packages modern system_dependencies)
assert_json_eq("${modern_system}" [[{"Foo":{"a":1,"b":2}}]] "system identities roundtrip canonically")
string(JSON schema GET "${content}" lock_schema)
assert_eq("${schema}" "1" "lock schema remains 1")

set_property(GLOBAL PROPERTY CDPM_LOCKFILE_LOADED FALSE)
cdpm_read_lockfile(PATH "${lock}")
cdpm_lockfile_get(modern found entry)
assert_true("${found}" "entry survives fresh read")
string(JSON reread_system GET "${entry}" system_dependencies)
assert_json_eq("${reread_system}" "${modern_system}" "system identities survive roundtrip")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: write.system_identities")
