include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/alias_deterministic_duplicate")
file(REMOVE_RECURSE "${tmp}")
foreach(name IN ITEMS alpha zeta)
    file(MAKE_DIRECTORY "${tmp}/${name}")
    file(WRITE "${tmp}/${name}/package.json"
        "{\"find_package_name\":\"SharedAlias\",\"source\":{\"type\":\"git\",\"url\":\"https://example.test/${name}.git\"},\"versions\":{\"1\":{\"rev\":\"0123456789abcdef0123456789abcdef01234567\"}}}")
endforeach()
file(WRITE "${tmp}/packages.json"
    [[{"version":1,"packages":{"zeta":"zeta/package.json","alpha":"alpha/package.json"}}]])

cdpm_load_repo("${tmp}/packages.json")
cdpm_find_package_in_repo(SharedAlias found package_key meta)
assert_true("${found}" "duplicate runtime alias resolves deterministically")
assert_eq("${package_key}" alpha "alias scan uses lexical canonical-key order")
cdpm_validate_registry("${tmp}" valid diagnostics)
assert_false("${valid}" "explicit full validation rejects duplicate aliases")
assert_match("${diagnostics}" "duplicate find_package_name.*alpha.*zeta" "duplicate diagnostic is canonical and stable")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: aliases are deterministic at runtime and duplicates fail full validation")
