# Test: load_repo.invalid_rev (WILL_FAIL)
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/invalid_rev")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(MAKE_DIRECTORY "${tmp}/packages/test")
file(WRITE "${tmp}/packages/test/package.json" [[{
  "source": {"type": "git", "url": "https://example.invalid/test.git"},
  "versions": {"1.0.0": {"rev": "01234567890123456789012345678901234567zz"}}
}]])
file(WRITE "${tmp}/packages.json" [[{
  "version": 1,
  "packages": {
    "test": "packages/test/package.json"
  }
}]])

cdpm_load_repo("${tmp}/packages.json")
cdpm_find_in_repo(test found meta)
message(STATUS "UNREACHABLE: non-hex rev should have aborted")
