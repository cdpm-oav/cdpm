include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/schema2_repeated_masks")
file(REMOVE_RECURSE "${tmp}")
foreach(package IN ITEMS a b)
    file(MAKE_DIRECTORY "${tmp}/first/${package}" "${tmp}/later/${package}")
    file(WRITE "${tmp}/first/${package}/package.json"
        "{\"source\":{\"type\":\"git\",\"url\":\"https://first.test/${package}.git\"},"
        "\"versions\":{\"1\":{\"rev\":\"0123456789abcdef0123456789abcdef01234567\"}}}")
    file(WRITE "${tmp}/later/${package}/package.json"
        "{\"source\":{\"type\":\"git\",\"url\":\"https://later.test/${package}.git\"},"
        "\"versions\":{\"1\":{\"rev\":\"0123456789abcdef0123456789abcdef01234567\"}}}")
endforeach()
file(WRITE "${tmp}/first/packages.json"
    [[{"repo_schema":2,"packages":{"a":"a/package.json","b":"b/package.json"}}]])
file(WRITE "${tmp}/later/packages.json"
    [[{"repo_schema":2,"packages":{"a":"a/package.json","b":"b/package.json"}}]])

_cdpm_registry_reset()
cdpm_load_repo("${tmp}/first/packages.json" PACKAGES [=[["a"]]=])
cdpm_load_repo("${tmp}/first/packages.json" PACKAGES [=[["b"]]=])
cdpm_load_repo("${tmp}/later/packages.json")

foreach(package IN ITEMS a b)
    cdpm_find_package_in_repo("${package}" found key meta)
    assert_true("${found}" "package '${package}' is claimed by its repeated schema-2 declaration")
    string(JSON url GET "${meta}" source url)
    assert_eq("${url}" "https://first.test/${package}.git"
        "first registration wins after repeated declarations with distinct masks")
endforeach()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: repeated schema-2 declarations apply every mask without changing registration priority")
