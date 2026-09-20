# Test: install/build slot helpers own the on-disk layout conventions.
cmake_policy(VERSION 3.25...4.0)

include(cdpm_basics)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

_cdpm_install_slot_dir("/store" "fmt" "0123456789abcdef" install_dir)
assert_eq("${install_dir}" "/store/fmt/0123456789abcdef" "install slot is <store>/<name>/<hash>")

_cdpm_build_slot_dir("/runtime" "fmt" "0123456789abcdef" build_dir)
assert_eq("${build_dir}" "/runtime/bs/fmt-0123456789abcdef" "build slot is <runtime>/bs/<name>-<hash>")

message(STATUS "PASS: cdpm_basics slot helpers")
