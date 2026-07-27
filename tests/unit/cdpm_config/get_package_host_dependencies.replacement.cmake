include(cdpm_config)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(meta [[{"host_dependencies":{"perl":{"version":"5.44.0"}},"versions":{"1":{},"2":{"host_dependencies":{"nasm":{"version":"2.16.03"}}}}}]])
cdpm_get_package_host_dependencies(pkg "${meta}" 1 package_dependencies)
cdpm_get_package_host_dependencies(pkg "${meta}" 2 version_dependencies)
assert_json_eq("${package_dependencies}" [[{"perl":{"version":"5.44.0"}}]] "package host dependencies")
assert_json_eq("${version_dependencies}" [[{"nasm":{"version":"2.16.03"}}]] "version map replaces package map")
message(STATUS "PASS: get_package_host_dependencies.replacement")
