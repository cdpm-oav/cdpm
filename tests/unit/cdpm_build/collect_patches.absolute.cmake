# Test: collect_patches.absolute
include(cdpm_build)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# cdpm_collect_patches returns declared patches as an absolute-path JSON array in
# apply order; the driver later feeds these to ExternalProject's PATCH_COMMAND.
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/collect_patches")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")
file(WRITE "${tmp}/0001-a.patch" "x\n")
file(WRITE "${tmp}/0002-b.patch" "y\n")

set(meta "{\"versions\":{\"1.0.0\":{\"patches\":[\"${tmp}/0001-a.patch\",\"${tmp}/0002-b.patch\"]}}}")

cdpm_collect_patches("demo" "1.0.0" "${meta}" patches)

string(JSON n LENGTH "${patches}")
assert_eq("${n}" "2" "two patches collected")
string(JSON p0 GET "${patches}" 0)
string(JSON p1 GET "${patches}" 1)
assert_eq("${p0}" "${tmp}/0001-a.patch" "first patch absolute, order preserved")
assert_eq("${p1}" "${tmp}/0002-b.patch" "second patch absolute, order preserved")

# No patches -> empty array.
cdpm_collect_patches("demo" "1.0.0" "{\"versions\":{\"1.0.0\":{}}}" empty)
assert_eq("${empty}" "[]" "no patches yields an empty array")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: cdpm_collect_patches returns ordered absolute patch paths")
