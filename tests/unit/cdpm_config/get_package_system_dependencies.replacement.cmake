# Test: get_package_system_dependencies.replacement
include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(meta [=[{
  "system_dependencies":{"Zlib":{"mode":"config","identity_targets":["ZLIB::ZLIB"],
    "identity_paths":["./include/zlib.h"]}},
  "versions":{"2":{"system_dependencies":{"Threads":{"mode":"MoDuLe","components":["C"],
    "identity_targets":["Threads::Threads"]}}}}
}]=])

cdpm_get_package_system_dependencies("consumer" "${meta}" "1" package_level)
assert_json_eq("${package_level}"
    [[{"Zlib":{"identity_paths":["include/zlib.h"],"identity_targets":["ZLIB::ZLIB"],"mode":"CONFIG"}}]]
    "package-level system dependencies are canonicalized")

cdpm_get_package_system_dependencies("consumer" "${meta}" "2" version_level)
assert_json_eq("${version_level}"
    [[{"Threads":{"components":["C"],"identity_targets":["Threads::Threads"],"mode":"MODULE"}}]]
    "per-version map replaces package-level map")

message(STATUS "PASS: get_package_system_dependencies.replacement")
