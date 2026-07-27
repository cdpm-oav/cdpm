cmake_policy(SET CMP0011 NEW)
include(cdpm_resolve)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/host-reject")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
set(CDPM_PROJECT_DIR "${tmp}")
set(CDPM_STORE_DIR "${tmp}/store")
set_property(GLOBAL PROPERTY CDPM_CONFIG_LOADED TRUE)
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG [[{"packages":{},"options":{},"user":{}}]])
set_property(GLOBAL PROPERTY CDPM_REPO_JSON [[{"repos":[]}]])
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO [[{"packages":{
  "leaf":{"source":{"type":"local","url":"."},"default_version":"1","versions":{"1":{}}},
  "badtool":{"source":{"type":"local","url":"."},"default_version":"1","dependencies":{"leaf":{}},"versions":{"1":{}}},
  "root":{"source":{"type":"local","url":"."},"default_version":"1","host_dependencies":{"badtool":{"version":"1"}},"versions":{"1":{}}}
}}]])
cdpm_resolve_and_build(root "" context)
