# Test: load_repos.git_missing_baseline
# A kind=git repo without a 'baseline' pin is fatal.
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/load_repos_git_no_baseline")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

file(WRITE "${tmp}/cdpm.json"
[[{"cdpm_schema":1,"repos":[{"kind":"git","url":"https://example/repo.git"}]}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "")
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "")
cdpm_config_load(FORCE)

# Expected to abort with FATAL_ERROR (registered WILL_FAIL TRUE).
cdpm_load_repos()

message(FATAL_ERROR "FAIL: expected FATAL_ERROR for kind=git without baseline, but got none")
