# Test: compute.system_identities
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_BUILD_TYPE Release)
set(CMAKE_GENERATOR Ninja)

cdpm_compute_config_hash(x 1 "{}" baseline)
cdpm_compute_config_hash(x 1 "{}" first SYSTEM_IDENTITIES [[{"Foo":{"b":2,"a":1}}]])
cdpm_compute_config_hash(x 1 "{}" reordered SYSTEM_IDENTITIES [[{"Foo":{"a":1,"b":2}}]])
cdpm_compute_config_hash(x 1 "{}" changed SYSTEM_IDENTITIES [[{"Foo":{"a":1,"b":3}}]])

assert_eq("${first}" "${reordered}" "canonical key order does not change hash")
assert_ne("${baseline}" "${first}" "supplying identities changes hash")
assert_ne("${first}" "${changed}" "identity content changes hash")
message(STATUS "PASS: compute.system_identities")
