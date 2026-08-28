include(cdpm_resolve)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/nested_skip_commit")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/src/pkg")

set(meta [[{
    "source":{"type":"local","url":"SRC_DIR"},
    "default_version":"1",
    "versions":{"1":{}}
}]])
string(REPLACE "SRC_DIR" "${tmp}/src/pkg" meta "${meta}")

function(cdpm_load_repos)
    # No-op: the registry is seeded manually below.
endfunction()

function(cdpm_build_dependency pkg version hash meta)
    file(MAKE_DIRECTORY "${CDPM_STORE_DIR}/${pkg}/${hash}")
    file(TOUCH "${CDPM_STORE_DIR}/${pkg}/${hash}/.cdpm_installed")
endfunction()

set(CDPM_PROJECT_DIR "${tmp}")
set(CDPM_STORE_DIR "${tmp}/store")
set(CDPM_LOCKFILE_PATH "${tmp}/lock.json")
set(CDPM_RUNTIME_DIR "${tmp}/runtime")

set_property(GLOBAL PROPERTY CDPM_CONFIG_LOADED TRUE)
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG [[{"packages":{},"options":{},"user":{}}]])
set_property(GLOBAL PROPERTY CDPM_REPO_JSON "{\"repos\":[]}")
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "{}")
set_property(GLOBAL PROPERTY CDPM_REGISTRY_OWNERS "{}")
set_property(GLOBAL PROPERTY CDPM_REGISTRY_ALIAS_CACHE "")
set_property(GLOBAL PROPERTY CDPM_SCHEMA2_REGISTRY_IDS "")
set_property(GLOBAL PROPERTY CDPM_REPO_PROVENANCE "")
set_property(GLOBAL PROPERTY CDPM_LOCKFILE_LOADED FALSE)

set(merged "{}")
string(JSON merged SET "${merged}" packages "{}")
string(JSON merged SET "${merged}" packages pkg "${meta}")
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "${merged}")

set_property(GLOBAL PROPERTY __CDPM_RESOLVER_NESTED TRUE)

cdpm_resolve_and_build(pkg "" ctx LOCK_MODE UPDATE)

if(EXISTS "${CDPM_LOCKFILE_PATH}")
    message(FATAL_ERROR "FAIL: nested UPDATE resolver committed lockfile entries")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: nested resolver skips lockfile commits")
