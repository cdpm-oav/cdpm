# Test: load_repo.bad_version_range (WILL_FAIL)
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# A malformed version_options range is a registry authoring error -> fatal at load.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/bad_range")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(MAKE_DIRECTORY "${tmp}/packages/test")
file(WRITE "${tmp}/packages/test/package.json"
[[{
  "source": {
    "type": "git",
    "url": "https://example/test.git"
  },
  "version_options": [
    {
      "range": "[10.0~~12.0)",
      "options": {
        "X": "ON"
      }
    }
  ],
  "versions": {
    "1.0.0": {
      "rev": "deadbeefcafedeadbeefcafedeadbeefdeadbeef"
    }
  }
}]])
file(WRITE "${tmp}/packages.json"
[[{
  "version": 1,
  "packages": {
    "test": "packages/test/package.json"
  }
}]]
)

set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "")
cdpm_load_repo("${tmp}/packages.json")
cdpm_find_in_repo(test found meta)

message(STATUS "UNREACHABLE: bad version_options range should have aborted")
