cmake_policy(SET CMP0140 NEW)

function(write_registry_manifest path)
    file(WRITE "${path}"
        [[{"find_package_name":"Demo","source":{"type":"git","url":"https://example.test/demo.git"},]]
        [["default_version":"1.0.0","versions":{"1.0.0":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}]])
endfunction()

function(init_registry_fixture name out_dir)
    set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/${name}")
    file(REMOVE_RECURSE "${tmp}")
    file(MAKE_DIRECTORY "${tmp}/packages/demo")
    write_registry_manifest("${tmp}/packages/demo/package.json")
    set(${out_dir} "${tmp}")
    return(PROPAGATE ${out_dir})
endfunction()
