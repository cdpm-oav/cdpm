# Test: load_repo.invalid_sha256 (WILL_FAIL)
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/invalid_sha256")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(MAKE_DIRECTORY "${tmp}/packages/test")
file(WRITE "${tmp}/packages/test/package.json" [[{
  "source": {"type": "url", "url": "https://example.invalid/test.tar.gz"},
  "versions": {"1.0.0": {"sha256": "deadbeef"}}
}]])
file(WRITE "${tmp}/packages.json" [[{
  "version": 1,
  "packages": {
    "test": "packages/test/package.json"
  }
}]])

cdpm_load_repo("${tmp}/packages.json")
cdpm_find_in_repo(test found meta)
message(STATUS "UNREACHABLE: short sha256 should have aborted")
