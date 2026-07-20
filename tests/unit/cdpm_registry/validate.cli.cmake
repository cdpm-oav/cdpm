include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH unit_dir)
cmake_path(GET unit_dir PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)
set(cli "${cdpm_root}/cdpm-cli.cmake")
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/validate_cli")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/valid/demo" "${tmp}/invalid/demo")
file(WRITE "${tmp}/valid/demo/package.json" [[{"source":{"type":"git","url":"https://example.test/demo.git"},
"versions":{"1":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}]])
file(WRITE "${tmp}/valid/packages.json" [[{"repo_schema":2,"packages":{"demo":"demo/package.json"}}]])
file(WRITE "${tmp}/invalid/demo/package.json" "not-json")
file(WRITE "${tmp}/invalid/packages.json" [[{"repo_schema":2,"packages":{"demo":"demo/package.json"}}]])
file(SHA256 "${tmp}/valid/packages.json" before)

execute_process(COMMAND "${CMAKE_COMMAND}" -P "${cli}" -- help RESULT_VARIABLE help_result
    OUTPUT_VARIABLE help_out ERROR_VARIABLE help_err)
assert_eq("${help_result}" 0 "CLI help succeeds")
assert_match("${help_out}${help_err}" "validate-registry <path>" "CLI help documents validate-registry")
foreach(path IN ITEMS "${tmp}/valid" "${tmp}/valid/packages.json")
    execute_process(COMMAND "${CMAKE_COMMAND}" -P "${cli}" -- validate-registry "${path}"
        RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
    assert_eq("${result}" 0 "CLI accepts valid registry path form '${path}'")
endforeach()
execute_process(COMMAND "${CMAKE_COMMAND}" -P "${cli}" -- validate-registry "${tmp}/invalid"
    RESULT_VARIABLE invalid_result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(invalid_result EQUAL 0)
    message(FATAL_ERROR "FAIL: CLI accepted an invalid registry")
endif()
assert_match("${output}${error}" "Registry validation failed" "CLI failure has a clear diagnostic")
file(SHA256 "${tmp}/valid/packages.json" after)
assert_eq("${after}" "${before}" "CLI validation does not mutate the registry")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: validate-registry CLI help, path forms, status, diagnostics, and no mutation")
