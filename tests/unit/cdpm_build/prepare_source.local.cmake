# Test: prepare_source.local
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# A local source override is normalized to a {type:local, path:<abs>} JSON object.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/prep_local")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/src")
file(WRITE "${tmp}/src/CMakeLists.txt" "# marker\n")

set(CMAKE_BINARY_DIR "${tmp}/bin")

# Effective config carrying a local source_override (allowed via the flag).
set(eff "{\"allow_source_override\":true,\"packages\":{\"demo\":{\"source_override\":{\"type\":\"local\",\"path\":\"${tmp}/src\"}}}}")
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "${eff}")

set(meta [[{
    "source": {
        "type": "git",
        "url": "https://example/demo.git"
    },
    "versions": {
        "1.0.0": {
            "rev": "deadbeefcafedeadbeefcafedeadbeefdeadbeef"
        }
    }
}]])

cdpm_prepare_source("demo" "1.0.0" "${meta}" source_json)

assert_json_member("${source_json}" "type" "local" "source type is local")
assert_json_member("${source_json}" "path" "${tmp}/src" "local source path is normalized absolute")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm_prepare_source returns a normalized local source object")
