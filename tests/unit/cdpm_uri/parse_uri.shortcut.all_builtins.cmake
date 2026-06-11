# Test: parse_uri.shortcut.all_builtins
include("${CMAKE_SOURCE_DIR}/core/cdpm_uri.cmake")
include("${CMAKE_SOURCE_DIR}/tests/helpers.cmake")

set(cases
    "gh:u/r"        "https://github.com/u/r.git"
    "github:u/r"    "https://github.com/u/r.git"
    "gl:u/r"        "https://gitlab.com/u/r.git"
    "gitlab:u/r"    "https://gitlab.com/u/r.git"
    "bb:u/r"        "https://bitbucket.org/u/r.git"
    "bitbucket:u/r" "https://bitbucket.org/u/r.git"
    "cb:u/r"        "https://codeberg.org/u/r.git"
    "codeberg:u/r"  "https://codeberg.org/u/r.git"
)

list(LENGTH cases n)
math(EXPR last "${n} - 1")
foreach(i RANGE 0 ${last} 2)
    math(EXPR j "${i} + 1")
    list(GET cases ${i} uri)
    list(GET cases ${j} expected_uri)
    cdpm_parse_uri("${uri}" PREFIX dep)
    assert_eq("${dep_SCHEME_TYPE}" "GIT_SHORTCUT"   "scheme type for ${uri}")
    assert_eq("${dep_FULL_URI}"    "${expected_uri}" "full URI for ${uri}")
endforeach()
message(STATUS "PASS: all built-in shortcuts expand correctly")

