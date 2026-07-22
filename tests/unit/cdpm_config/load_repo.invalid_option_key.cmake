# Test: load_repo.invalid_option_key (WILL_FAIL)
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/invalid_option_key")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(MAKE_DIRECTORY "${tmp}/packages/test")
file(WRITE "${tmp}/packages/test/package.json" [[{
  "source": {"type": "git", "url": "https://example.invalid/test.git"},
  "options": {") message(FATAL_ERROR injected)": "ON"},
  "versions": {"1.0.0": {"rev": "0123456789012345678901234567890123456789"}}
}]])
file(WRITE "${tmp}/packages.json" [[{
  "version": 1,
  "packages": {
    "test": "packages/test/package.json"
  }
}]])

cdpm_load_repo("${tmp}/packages.json")
cdpm_find_in_repo(test found meta)
message(STATUS "UNREACHABLE: unsafe option key should have aborted")
