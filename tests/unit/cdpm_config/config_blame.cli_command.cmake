# Test: config_blame.cli_command
include(cdpm_cli_commands)
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# cdpm_cmd_config_blame is the CLI wrapper over cdpm_config_blame. In OUTPUT mode it returns the
# flat `path;label;...` list and prints nothing -- this is the strictly testable path (and the
# reusable pattern for other CLI-command tests).
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/config_blame_cli")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

# project sets options + packages.fmt; user overrides options and adds packages.zlib.
file(WRITE "${tmp}/cdpm.json"
[[{"cdpm_schema":1,"options":{"SHARED":true},"packages":{"fmt":{"version":"1.0.0"}}}]])
file(WRITE "${tmp}/cdpm_user.json"
[[{"options":{"SHARED":false},"packages":{"zlib":{"version":"2.0.0"}}}]])

set(CDPM_MACHINE_CONFIG "")
set(CDPM_PROJECT_CONFIG "${tmp}/cdpm.json")
set(CDPM_USER_CONFIG    "${tmp}/cdpm_user.json")

# Single-path blame: packages.fmt comes only from the project layer.
cdpm_cmd_config_blame("packages.fmt" OUTPUT blame_fmt)
list(GET blame_fmt 0 path_fmt)
list(GET blame_fmt 1 label_fmt)
assert_eq("${path_fmt}"  "packages.fmt" "wrapper echoes the requested path")
assert_eq("${label_fmt}" "2/project"    "packages.fmt set by the project layer")

# options is touched by both layers -> the user layer (3) wins (last writer).
cdpm_cmd_config_blame("options" OUTPUT blame_options)
list(GET blame_options 1 label_options)
assert_eq("${label_options}" "3/user" "options last set by the user layer")

# An unrecorded path reports <unset>.
cdpm_cmd_config_blame("nope.absent" OUTPUT blame_absent)
list(GET blame_absent 1 label_absent)
assert_eq("${label_absent}" "<unset>" "unrecorded path reports <unset>")

# Blame-all: empty path returns every recorded origin (flat path;label list).
cdpm_cmd_config_blame("" OUTPUT blame_all)
assert_ne("${blame_all}" "" "blame-all returns a non-empty list")
list(FIND blame_all "packages.fmt" idx_fmt)
assert_ne("${idx_fmt}" "-1" "blame-all includes packages.fmt")
list(FIND blame_all "options" idx_options)
assert_ne("${idx_options}" "-1" "blame-all includes options")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm_cmd_config_blame OUTPUT mode returns blame data without printing")
