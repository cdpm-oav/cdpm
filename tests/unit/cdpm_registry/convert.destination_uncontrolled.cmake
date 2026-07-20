include(cdpm_registry_converter)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/convert_destination_uncontrolled")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/project" "${tmp}/destination")
file(WRITE "${tmp}/destination/keep.txt" "must survive")
file(WRITE "${tmp}/source.json" [[{"repo_schema":1,"packages":{"demo":{"source":{"type":"git",
"url":"https://example.test/demo.git"},"versions":{"1.0.0":{"rev":"0123456789abcdef0123456789abcdef01234567"}}}}}]])
cdpm_convert_registry_schema1_to_schema2(SOURCE "${tmp}/source.json" DESTINATION "${tmp}/destination"
    PROJECT_DIR "${tmp}/project")
