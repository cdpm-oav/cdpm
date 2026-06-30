# Test: add_registry.cli_command
include(cdpm_cli_commands)
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# cdpm_cmd_add_registry must persist a kind=file repos[] entry into a config layer that
# cdpm_config_load() actually reads -- not into an ephemeral cache variable (cmake -P keeps no
# cache). The *_CONFIG overrides point both layers at a scratch dir so the command is testable.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/add_registry_cli")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

set(CDPM_MACHINE_CONFIG "${tmp}/config.json")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "")

# A minimal valid registry: a local-source package needs no per-version integrity pin.
set(registry "${tmp}/packages.json")
file(WRITE "${registry}"
[[{"repo_schema":1,"packages":{"demo":{"source":{"type":"local","url":"/tmp/demo-src"},"default_version":"1.0.0","versions":{"1.0.0":{}}}}}]])
cmake_path(ABSOLUTE_PATH registry NORMALIZE OUTPUT_VARIABLE registry_abs)

# --- machine scope: a fresh config file is created carrying the repos[] entry ---------------
cdpm_cmd_add_registry("${registry}" "machine")
if(EXISTS "${CDPM_MACHINE_CONFIG}")
    set(machine_exists TRUE)
else()
    set(machine_exists FALSE)
endif()
assert_true("${machine_exists}" "machine config file is created")

file(READ "${CDPM_MACHINE_CONFIG}" machine_json)
string(JSON machine_type TYPE "${machine_json}")
assert_eq("${machine_type}" "OBJECT" "machine config is a JSON object")
string(JSON repos_len LENGTH "${machine_json}" "repos")
assert_eq("${repos_len}" "1" "machine config has exactly one repos[] entry")
string(JSON entry_kind GET "${machine_json}" "repos" 0 "kind")
string(JSON entry_path GET "${machine_json}" "repos" 0 "path")
assert_eq("${entry_kind}" "file"            "entry kind is file")
assert_eq("${entry_path}" "${registry_abs}" "entry path is the absolute registry path")

# --- idempotency: re-adding the same registry does not duplicate the entry ------------------
cdpm_cmd_add_registry("${registry}" "machine")
file(READ "${CDPM_MACHINE_CONFIG}" machine_json2)
string(JSON repos_len2 LENGTH "${machine_json2}" "repos")
assert_eq("${repos_len2}" "1" "re-adding the same registry is a no-op (dedup)")

# --- project scope: writes the project cdpm.json instead --------------------------------------
cdpm_cmd_add_registry("${registry}" "project")
if(EXISTS "${CDPM_PROJECT_CONFIG}")
    set(project_exists TRUE)
else()
    set(project_exists FALSE)
endif()
assert_true("${project_exists}" "project config file is created")
file(READ "${CDPM_PROJECT_CONFIG}" project_json)
string(JSON proj_repos_len LENGTH "${project_json}" "repos")
assert_eq("${proj_repos_len}" "1" "project config has the repos[] entry")

# --- end-to-end: the persisted registry is now actually consumed by the loader ---------------
# This is the real proof of the fix: previously add-registry wrote a dead cache variable and
# the package was never findable. Disable the project layer so only the machine entry is used.
set(CDPM_PROJECT_CONFIG "")
cdpm_config_load(FORCE)
cdpm_load_repos()
cdpm_find_in_repo("demo" found meta)
assert_true("${found}" "package from the added registry is found after config load")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: add-registry persists a repos[] entry that cdpm_load_repos() consumes")
