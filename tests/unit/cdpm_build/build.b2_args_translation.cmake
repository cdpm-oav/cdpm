# Test: build.b2_args_translation
#
# Verifies b2 helper functions translate options and metadata into the expected
# bootstrap and build argument lists.

include(bs/cdpm_bs_b2)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# ---------------------------------------------------------------------------
# _cdpm_b2_libraries
# ---------------------------------------------------------------------------
set(ctx_json [[{"options":{"BOOST_BUILD_LIBRARIES":"filesystem;system"}}]])
_cdpm_b2_libraries("${ctx_json}" libs)
foreach(_item IN ITEMS "--with-filesystem" "--with-system")
    list(FIND libs "${_item}" _found)
    if(_found EQUAL -1)
        message(FATAL_ERROR "FAIL: expected '${_item}' in libraries result\n  result: ${libs}")
    endif()
endforeach()

# Empty library list means no --with- flags.
set(ctx_json_empty [[{"options":{}}]])
_cdpm_b2_libraries("${ctx_json_empty}" libs_empty)
assert_empty("${libs_empty}" "_cdpm_b2_libraries for empty library list")

# ---------------------------------------------------------------------------
# _cdpm_b2_link_mode
# ---------------------------------------------------------------------------
set(ctx_json [[{"options":{"BOOST_LINK":"static"}}]])
_cdpm_b2_link_mode("${ctx_json}" link)
assert_eq("${link}" "static" "_cdpm_b2_link_mode for static")

set(ctx_json [[{"options":{"BOOST_LINK":"shared"}}]])
_cdpm_b2_link_mode("${ctx_json}" link)
assert_eq("${link}" "shared" "_cdpm_b2_link_mode for shared")

set(ctx_json "{}")
_cdpm_b2_link_mode("${ctx_json}" link)
assert_eq("${link}" "shared" "_cdpm_b2_link_mode default")

# ---------------------------------------------------------------------------
# _cdpm_b2_bootstrap_args
# ---------------------------------------------------------------------------
set(ctx_json [[{"build":{}}]])
_cdpm_b2_bootstrap_args("${ctx_json}" "gcc" bootstrap)
list(FIND bootstrap "--with-toolset=gcc" _found)
if(_found EQUAL -1)
    message(FATAL_ERROR "FAIL: expected '--with-toolset=gcc' in bootstrap args\n  result: ${bootstrap}")
endif()

set(ctx_json [[{"build":{"bootstrap_args":["--with-libraries=filesystem"]}}]])
_cdpm_b2_bootstrap_args("${ctx_json}" "clang" bootstrap)
foreach(_item IN ITEMS "--with-toolset=clang" "--with-libraries=filesystem")
    list(FIND bootstrap "${_item}" _found)
    if(_found EQUAL -1)
        message(FATAL_ERROR "FAIL: expected '${_item}' in bootstrap args\n  result: ${bootstrap}")
    endif()
endforeach()

# ---------------------------------------------------------------------------
# _cdpm_b2_build_args
# ---------------------------------------------------------------------------
set(ctx_json [[{
    "install_dir":"/tmp/install",
    "build_dir":"/tmp/build",
    "options":{
        "BOOST_LINK":"static",
        "BOOST_BUILD_LIBRARIES":"filesystem;system"
    },
    "build":{
        "parallel":false
    }
}]])

_cdpm_b2_build_args("${ctx_json}" "gcc" "release" "64" "static" "${libs}" args)

foreach(_item IN ITEMS
    "toolset=gcc"
    "variant=release"
    "link=static"
    "address-model=64"
    "--layout=versioned"
    "--prefix=/tmp/install"
    "--without-python"
    "--disable-icu"
    "--with-filesystem"
    "--with-system"
)
    list(FIND args "${_item}" _found)
    if(_found EQUAL -1)
        message(FATAL_ERROR "FAIL: expected '${_item}' in build args\n  result: ${args}")
    endif()
endforeach()

message(STATUS "PASS: build.b2_args_translation")
