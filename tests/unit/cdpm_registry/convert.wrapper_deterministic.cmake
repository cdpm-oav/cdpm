include(cdpm_registry_converter)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/convert_wrapper")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/project/assets/alpha" "${tmp}/project/assets/beta")
file(WRITE "${tmp}/project/assets/alpha/shared.diff" "alpha shared\n")
file(WRITE "${tmp}/project/assets/alpha/version.diff" "alpha version\n")
file(WRITE "${tmp}/project/assets/beta/shared.diff" "beta shared\n")
set(alpha [[{"find_package_name":"Alpha","source":{"type":"git","url":"https://example.test/alpha.git"},
"default_version":"1.0.0","patches":[{"file":"assets/alpha/shared.diff","applies_to":"[1.0.0->2.0.0)",
"exclude":["1.5.0"]}],"versions":{"1.0.0":{"rev":"1111111111111111111111111111111111111111",
"patches":["assets/alpha/shared.diff","assets/alpha/version.diff"]}}}]])
set(beta [[{"find_package_name":"Beta","source":{"type":"git","url":"https://example.test/beta.git"},
"default_version":"2.0.0","versions":{"2.0.0":{"rev":"2222222222222222222222222222222222222222",
"patches":["assets/beta/shared.diff"]}}}]])
file(WRITE "${tmp}/source.json" "{\"repo_schema\":1,\"packages\":{\"Beta\":${beta},\"ALPHA\":${alpha}}}")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH unit_dir)
cmake_path(GET unit_dir PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)
set(wrapper "${cdpm_root}/tools/convert-registry-schema1-to-schema2.cmake")
foreach(destination IN ITEMS out-a out-b)
    execute_process(COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE=${tmp}/source.json" "-DDESTINATION=${tmp}/${destination}"
            "-DPROJECT_DIR=${tmp}/project" -P "${wrapper}"
        RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
    )
    assert_eq("${result}" 0 "the maintenance wrapper succeeds: ${output}${error}")
    cdpm_validate_registry("${tmp}/${destination}" valid diagnostics)
    assert_true("${valid}" "generated registry passes production validation: ${diagnostics}")
endforeach()

file(GLOB_RECURSE first_files RELATIVE "${tmp}/out-a" "${tmp}/out-a/*")
file(GLOB_RECURSE second_files RELATIVE "${tmp}/out-b" "${tmp}/out-b/*")
list(SORT first_files)
list(SORT second_files)
assert_eq("${second_files}" "${first_files}" "repeated conversion emits the same file list")
foreach(relative IN LISTS first_files)
    if(IS_DIRECTORY "${tmp}/out-a/${relative}")
        continue()
    endif()
    file(READ "${tmp}/out-a/${relative}" first)
    file(READ "${tmp}/out-b/${relative}" second)
    assert_eq("${second}" "${first}" "${relative} is byte-stable")
endforeach()

file(READ "${tmp}/out-a/packages.json" index)
assert_json_eq("${index}" [[{"repo_schema":2,"packages":{"alpha":"packages/alpha/package.json",
"beta":"packages/beta/package.json"}}]] "root index contains only canonical manifest locators")
file(READ "${tmp}/out-a/packages/alpha/package.json" manifest)
string(JSON package_patch GET "${manifest}" patches 0 file)
string(JSON version_shared GET "${manifest}" versions 1.0.0 patches 0)
string(JSON version_unique GET "${manifest}" versions 1.0.0 patches 1)
assert_eq("${package_patch}" patches/shared.diff "package patch is manifest-relative")
assert_eq("${version_shared}" patches/shared.diff "one declared asset is shared without duplication")
assert_eq("${version_unique}" patches/version.diff "different patch filenames preserve order")
file(READ "${tmp}/out-a/packages/alpha/patches/shared.diff" alpha_bytes)
file(READ "${tmp}/out-a/packages/beta/patches/shared.diff" beta_bytes)
assert_eq("${alpha_bytes}" "alpha shared\n" "alpha owns its patch bytes")
assert_eq("${beta_bytes}" "beta shared\n" "same filename is isolated by package")

# A marked destination is controlled and may be refreshed in place.
execute_process(COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE=${tmp}/source.json" "-DDESTINATION=${tmp}/out-a" "-DPROJECT_DIR=${tmp}/project"
        -P "${wrapper}"
    RESULT_VARIABLE rerun_result ERROR_VARIABLE rerun_error
)
assert_eq("${rerun_result}" 0 "wrapper safely refreshes its own destination: ${rerun_error}")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: converter wrapper is deterministic and validates generated output")
