# Test: load_repo.invalid_sha256 (WILL_FAIL)
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/invalid_sha256")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/packages.json" [[{
  "repo_schema": 1,
  "packages": {
    "test": {
      "source": {"type": "url", "url": "https://example.invalid/test.tar.gz"},
      "versions": {"1.0.0": {"sha256": "deadbeef"}}
    }
  }
}]])

cdpm_load_repo("${tmp}/packages.json")
message(STATUS "UNREACHABLE: short sha256 should have aborted")
