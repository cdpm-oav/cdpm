include(cdpm_registry_converter)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/convert_patch_missing")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/project")
file(WRITE "${tmp}/source.json" [[{"repo_schema":1,"packages":{"demo":{"source":{"type":"git",
"url":"https://example.test/demo.git"},"patches":[{"file":"missing.diff"}],
"versions":{"1.0.0":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}}}]])
cdpm_convert_registry_schema1_to_schema2(SOURCE "${tmp}/source.json" DESTINATION "${tmp}/destination"
    PROJECT_DIR "${tmp}/project")
