# Test: load_repo.invalid_rev (WILL_FAIL)
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/invalid_rev")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/packages.json" [[{
  "repo_schema": 1,
  "packages": {
    "test": {
      "source": {"type": "git", "url": "https://example.invalid/test.git"},
      "versions": {"1.0.0": {"rev": "01234567890123456789012345678901234567zz"}}
    }
  }
}]])

cdpm_load_repo("${tmp}/packages.json")
message(STATUS "UNREACHABLE: non-hex rev should have aborted")
