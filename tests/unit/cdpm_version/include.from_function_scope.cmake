# Test: include.from_function_scope
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/include_from_function_scope")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/VERSION" "4.5.6\n")

function(include_version_from_function)
    set(__CDPM_VERSION_FILE "${tmp}/VERSION")
    include(cdpm_version)
endfunction()

include_version_from_function()

_cdpm_get_version(version)
assert_eq("${version}" "4.5.6" "function-scoped first include preserves VERSION override")

cdpm_parse_version_range("1..2" low high low_incl high_incl ok)
assert_false("${ok}" "function-scoped first include retains strict numeric range parsing")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm_version survives first include from function scope")
