# Test: config_blame.layer_origins
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# cdpm_config_blame reports the last layer that set a tracked path.
# Origins are tracked at top-level + one level into packages/user/options.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/config_blame")
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
cdpm_config_load(FORCE)

# 'options' touched by both layers -> the user layer (3) wins (last writer).
cdpm_config_blame(PATH "options" OUTPUT blame_options)
list(GET blame_options 1 label_options)
assert_eq("${label_options}" "3/user" "options last set by the user layer")

# packages.fmt only from the project layer.
cdpm_config_blame(PATH "packages.fmt" OUTPUT blame_fmt)
list(GET blame_fmt 1 label_fmt)
assert_eq("${label_fmt}" "2/project" "packages.fmt set by the project layer")

# packages.zlib only from the user layer.
cdpm_config_blame(PATH "packages.zlib" OUTPUT blame_zlib)
list(GET blame_zlib 1 label_zlib)
assert_eq("${label_zlib}" "3/user" "packages.zlib set by the user layer")

# An unrecorded path reports <unset>.
cdpm_config_blame(PATH "nope.absent" OUTPUT blame_absent)
list(GET blame_absent 1 label_absent)
assert_eq("${label_absent}" "<unset>" "unrecorded path reports <unset>")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm_config_blame reports the last layer per tracked path")
