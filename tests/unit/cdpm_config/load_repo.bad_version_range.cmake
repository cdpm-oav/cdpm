# Test: load_repo.bad_version_range (WILL_FAIL)
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# A malformed version_options range is a registry authoring error -> fatal at load.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/bad_range")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/packages.json"
[[{
  "repo_schema": 1,
  "packages": {
    "test": {
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
    }
  }
}]]
)

set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "")
cdpm_load_repo("${tmp}/packages.json")

message(STATUS "UNREACHABLE: bad version_options range should have aborted")
