# Integration: host_tool_graph
#
# Offline end-to-end proof of host/target separation. A local registry contains a
# host-only executable package and a target package that uses it at build time via
# find_program() + add_custom_command(). cdpm_resolve_and_build() builds the host
# graph with the native HOST toolchain and the target graph with the target
# toolchain, routes the host prefix into CMAKE_PROGRAM_PATH but not
# CMAKE_PREFIX_PATH, and records both graphs in the lockfile.
include(cdpm_resolve)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/host_tool_graph")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/sources/host-tool-pkg" "${tmp}/sources/target-pkg"
    "${tmp}/registry/packages" "${tmp}/project")

set(registry_dir "${tmp}/registry")
set(project_dir "${tmp}/project")
set(CDPM_PROJECT_DIR "${project_dir}")
set(CDPM_STORE_DIR "${tmp}/store")
set(CDPM_RUNTIME_DIR "${tmp}/runtime")

# ---- host-tool-pkg source: a tiny executable that target-pkg will run ----------
file(WRITE "${tmp}/sources/host-tool-pkg/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(host_tool_pkg NONE)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/host-tool"
    "#!/bin/sh\nif [ -n \"$1\" ]; then\n  echo \"hello from host-tool\" > \"$1\"\nelse\n  echo \"hello from host-tool\"\nfi\n")
file(CHMOD "${CMAKE_CURRENT_BINARY_DIR}/host-tool"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
install(PROGRAMS "${CMAKE_CURRENT_BINARY_DIR}/host-tool" DESTINATION bin)
]=])

# ---- target-pkg source: uses find_program() and add_custom_command() ------------
file(WRITE "${tmp}/sources/target-pkg/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.25)
project(target_pkg NONE)
find_program(HOST_TOOL_EXECUTABLE NAMES host-tool REQUIRED)
message(STATUS "target-pkg: HOST_TOOL_EXECUTABLE=${HOST_TOOL_EXECUTABLE}")

# Record the search paths and the discovered path for the test to inspect.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/prefix_path.txt" "${CMAKE_PREFIX_PATH}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/program_path.txt" "${CMAKE_PROGRAM_PATH}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/host_tool_path.txt" "${HOST_TOOL_EXECUTABLE}")

add_custom_command(
    OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/generated.txt"
    COMMAND "${HOST_TOOL_EXECUTABLE}" "${CMAKE_CURRENT_BINARY_DIR}/generated.txt"
    VERBATIM
)
add_custom_target(generate ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/generated.txt")
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/generated.txt"
    "${CMAKE_CURRENT_BINARY_DIR}/prefix_path.txt"
    "${CMAKE_CURRENT_BINARY_DIR}/program_path.txt"
    "${CMAKE_CURRENT_BINARY_DIR}/host_tool_path.txt"
    DESTINATION share
)
]=])

# ---- Local registry -----------------------------------------------------------
file(WRITE "${registry_dir}/packages/host-tool-pkg/package.json" "${registry_dir}/packages/host-tool-pkg/package.json")
file(WRITE "${registry_dir}/packages/target-pkg/package.json" "${registry_dir}/packages/target-pkg/package.json")

set(host_tool_manifest "${registry_dir}/packages/host-tool-pkg/package.json")
set(target_pkg_manifest "${registry_dir}/packages/target-pkg/package.json")

file(WRITE "${host_tool_manifest}" "{")
file(APPEND "${host_tool_manifest}" "\n  \"build_system\": \"cmake\",")
file(APPEND "${host_tool_manifest}" "\n  \"source\": { \"type\": \"local\", \"url\": \"${tmp}/sources/host-tool-pkg\" },")
file(APPEND "${host_tool_manifest}" "\n  \"default_version\": \"1.0.0\",")
file(APPEND "${host_tool_manifest}" "\n  \"versions\": { \"1.0.0\": {} }")
file(APPEND "${host_tool_manifest}" "\n}")

file(WRITE "${target_pkg_manifest}" "{")
file(APPEND "${target_pkg_manifest}" "\n  \"build_system\": \"cmake\",")
file(APPEND "${target_pkg_manifest}" "\n  \"source\": { \"type\": \"local\", \"url\": \"${tmp}/sources/target-pkg\" },")
file(APPEND "${target_pkg_manifest}" "\n  \"default_version\": \"1.0.0\",")
file(APPEND "${target_pkg_manifest}" "\n  \"host_dependencies\": { \"host-tool-pkg\": { \"version\": \"1.0.0\" } },")
file(APPEND "${target_pkg_manifest}" "\n  \"versions\": { \"1.0.0\": {} }")
file(APPEND "${target_pkg_manifest}" "\n}")

file(WRITE "${registry_dir}/packages.json" "{")
file(APPEND "${registry_dir}/packages.json" "\n  \"version\": 1,")
file(APPEND "${registry_dir}/packages.json" "\n  \"packages\": {")
file(APPEND "${registry_dir}/packages.json" "\n    \"host-tool-pkg\": \"packages/host-tool-pkg/package.json\",")
file(APPEND "${registry_dir}/packages.json" "\n    \"target-pkg\": \"packages/target-pkg/package.json\"")
file(APPEND "${registry_dir}/packages.json" "\n  }")
file(APPEND "${registry_dir}/packages.json" "\n}")

# ---- Project config pointing at the local registry ----------------------------
file(WRITE "${project_dir}/cdpm.json" "{")
file(APPEND "${project_dir}/cdpm.json" "\n  \"repos\": [ { \"kind\": \"file\", \"path\": \"${registry_dir}/packages.json\" } ]")
file(APPEND "${project_dir}/cdpm.json" "\n}")

# ---- Resolve and build target-pkg ---------------------------------------------
cdpm_resolve_and_build(target-pkg "" context)

# ---- Context-level checks -----------------------------------------------------
string(JSON host_managed_count LENGTH "${context}" host_managed)
string(JSON managed_count LENGTH "${context}" managed)
assert_eq("${host_managed_count}" 1 "host graph contains exactly one host node")
assert_eq("${managed_count}" 1 "target graph contains exactly the target node")

string(JSON host_tool_record GET "${context}" host_managed host-tool-pkg)
string(JSON target_record GET "${context}" managed target-pkg)

string(JSON host_prefix_count LENGTH "${context}" host_prefixes)
assert_eq("${host_prefix_count}" 1 "exactly one host prefix is exposed")
string(JSON host_prefix GET "${context}" host_prefixes 0)

string(JSON target_prefix_count LENGTH "${context}" prefixes)
assert_eq("${target_prefix_count}" 1 "exactly one target prefix is exposed")
string(JSON target_prefix GET "${context}" prefixes 0)

# ---- Lockfile separation ------------------------------------------------------
file(READ "${project_dir}/cdpm.lock.json" lock)
string(JSON host_packages_len LENGTH "${lock}" host_packages)
string(JSON packages_len LENGTH "${lock}" packages)
assert_eq("${host_packages_len}" 1 "lockfile host_packages section records host-tool-pkg")
assert_eq("${packages_len}" 1 "lockfile packages section records target-pkg")

# The target entry must record its host dependency identity.
string(JSON target_host_deps GET "${lock}" packages target-pkg host_dependencies)
string(JSON target_host_deps_len LENGTH "${target_host_deps}")
assert_eq("${target_host_deps_len}" 1 "target lock entry records host dependency")
string(JSON host_tool_identity GET "${target_host_deps}" host-tool-pkg)
string(JSON host_tool_identity_package GET "${host_tool_identity}" package)
assert_eq("${host_tool_identity_package}" "host-tool-pkg" "host dependency identity canonical name")

# ---- Install layout checks: host tool built into the store --------------------
string(JSON host_install_dir GET "${host_tool_record}" install_dir)
string(JSON target_install_dir GET "${target_record}" install_dir)
if(NOT EXISTS "${host_install_dir}/bin/host-tool")
    message(FATAL_ERROR "FAIL: host-tool executable was not installed at ${host_install_dir}/bin/host-tool")
endif()
if(NOT EXISTS "${target_install_dir}/share/generated.txt")
    message(FATAL_ERROR "FAIL: target-pkg did not install generated.txt")
endif()

# ---- find_program() found the host tool through CMAKE_PROGRAM_PATH ------------
file(READ "${target_install_dir}/share/host_tool_path.txt" found_host_tool)
string(STRIP "${found_host_tool}" found_host_tool)
assert_eq("${found_host_tool}" "${host_install_dir}/bin/host-tool"
    "find_program() resolved host-tool to the host store slot")

file(READ "${target_install_dir}/share/program_path.txt" target_program_path)
string(STRIP "${target_program_path}" target_program_path)
assert_match("${target_program_path}" "${host_install_dir}/bin"
    "target build sees the host prefix/bin in CMAKE_PROGRAM_PATH")

# ---- host prefix is NOT in the target CMAKE_PREFIX_PATH -----------------------
file(READ "${target_install_dir}/share/prefix_path.txt" target_prefix_path)
string(STRIP "${target_prefix_path}" target_prefix_path)
if("${target_prefix_path}" MATCHES "${host_install_dir}")
    message(FATAL_ERROR "FAIL: host prefix leaked into target CMAKE_PREFIX_PATH: ${target_prefix_path}")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: host_tool_graph")
