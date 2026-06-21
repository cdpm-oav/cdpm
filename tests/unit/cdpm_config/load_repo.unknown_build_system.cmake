# Test: load_repo.unknown_build_system
# A repo package declaring an unregistered build_system is fatal on load.
include(cdpm_config)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/repo_bad_bs")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/packages.json"
[[{"repo_schema":1,"packages":{"gmp":{"build_system":"frobnicate",
"source":{"type":"url","url":"https://example/gmp.tar.gz"},
"versions":{"6.3.0":{"sha256":"abc"}}}}}]])

# Expected to abort with FATAL_ERROR (registered WILL_FAIL TRUE).
cdpm_load_repo("${tmp}/packages.json")

message(FATAL_ERROR "FAIL: expected FATAL_ERROR for unknown build_system, but got none")
