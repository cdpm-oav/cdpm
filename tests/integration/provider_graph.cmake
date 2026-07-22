include("${CDPM_TEST_HELPERS}/helpers.cmake")
cmake_policy(SET CMP0140 NEW)

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)
set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/provider_graph")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/leaf" "${tmp}/parent" "${tmp}/bad" "${tmp}/consumer" "${tmp}/system/config"
    "${tmp}/system/module")
set(store "${tmp}/store")

file(WRITE "${tmp}/leaf/ManagedLeafConfig.cmake" "set(ManagedLeaf_FOUND TRUE)\n")
file(WRITE "${tmp}/leaf/CMakeLists.txt" [[cmake_minimum_required(VERSION 3.25)
project(leaf NONE)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/ManagedLeafConfig.cmake" DESTINATION lib/cmake/ManagedLeaf)
]])
file(WRITE "${tmp}/system/fake-config.bin" "config-one")
file(WRITE "${tmp}/system/fake-module.bin" "module-one")
file(WRITE "${tmp}/system/config/FakeConfigConfig.cmake"
    "set(FakeConfig_VERSION 1)\nadd_library(FakeConfig::Fake UNKNOWN IMPORTED)\n"
    "set_target_properties(FakeConfig::Fake PROPERTIES IMPORTED_LOCATION \"${tmp}/system/fake-config.bin\")\n")
file(WRITE "${tmp}/system/module/FindFakeModule.cmake"
    "set(FakeModule_FOUND TRUE)\nset(FakeModule_VERSION 1)\nadd_library(FakeModule::Fake UNKNOWN IMPORTED)\n"
    "set_target_properties(FakeModule::Fake PROPERTIES IMPORTED_LOCATION \"${tmp}/system/fake-module.bin\")\n")

file(WRITE "${tmp}/parent/ManagedParentConfig.cmake" [[include(CMakeFindDependencyMacro)
find_dependency(ManagedLeaf CONFIG)
find_dependency(FakeConfig CONFIG)
find_dependency(FakeModule MODULE)
set(ManagedParent_FOUND TRUE)
]])
file(WRITE "${tmp}/parent/CMakeLists.txt" [[cmake_minimum_required(VERSION 3.25)
project(parent NONE)
find_package(ManagedLeaf REQUIRED CONFIG)
find_package(FakeConfig REQUIRED CONFIG)
find_package(FakeModule REQUIRED MODULE)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/ManagedParentConfig.cmake" DESTINATION lib/cmake/ManagedParent)
]])
file(WRITE "${tmp}/bad/BadParentConfig.cmake" [[include(CMakeFindDependencyMacro)
find_dependency(UndeclaredNested CONFIG)
]])
file(WRITE "${tmp}/bad/CMakeLists.txt" [[cmake_minimum_required(VERSION 3.25)
project(bad NONE)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/BadParentConfig.cmake" DESTINATION lib/cmake/BadParent)
]])

file(MAKE_DIRECTORY "${tmp}/packages/leaf" "${tmp}/packages/parent" "${tmp}/packages/bad")
file(WRITE "${tmp}/packages/leaf/package.json" "{\"find_package_name\":\"ManagedLeaf\",\"source\":{\"type\":\"local\",\"url\":\"${tmp}/leaf\"},\"default_version\":\"1\",\"versions\":{\"1\":{}}}")
file(WRITE "${tmp}/packages/parent/package.json" "{\"find_package_name\":\"ManagedParent\",\"source\":{\"type\":\"local\",\"url\":\"${tmp}/parent\"},\"default_version\":\"1\",\"dependencies\":{\"leaf\":{}},\"system_dependencies\":{\"FakeConfig\":{\"mode\":\"CONFIG\",\"identity_targets\":[\"FakeConfig::Fake\"]},\"FakeModule\":{\"mode\":\"MODULE\",\"identity_targets\":[\"FakeModule::Fake\"]}},\"versions\":{\"1\":{}}}")
file(WRITE "${tmp}/packages/bad/package.json" "{\"find_package_name\":\"BadParent\",\"source\":{\"type\":\"local\",\"url\":\"${tmp}/bad\"},\"default_version\":\"1\",\"versions\":{\"1\":{}}}")
set(registry "${tmp}/packages.json")
file(WRITE "${registry}" "{\"version\":1,\"packages\":{"
    "\"leaf\":\"packages/leaf/package.json\","
    "\"parent\":\"packages/parent/package.json\","
    "\"bad\":\"packages/bad/package.json\"}}")
set(config "${tmp}/cdpm.json")
file(WRITE "${config}" "{\"allow_source_override\":true,"
    "\"repos\":[{\"kind\":\"file\",\"path\":\"${registry}\"}],\"packages\":{"
    "\"leaf\":{\"source_override\":{\"type\":\"local\",\"path\":\"${tmp}/leaf\"}},"
    "\"parent\":{\"source_override\":{\"type\":\"local\",\"path\":\"${tmp}/parent\"}},"
    "\"bad\":{\"source_override\":{\"type\":\"local\",\"path\":\"${tmp}/bad\"}}}}")
file(WRITE "${tmp}/consumer/CMakeLists.txt" [[cmake_minimum_required(VERSION 3.25)
project(consumer NONE)
find_package(ManagedParent REQUIRED CONFIG)
]])

function(configure_consumer build out_hash)
    execute_process(COMMAND "${CMAKE_COMMAND}" -S "${tmp}/consumer" -B "${build}"
        "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cdpm_root}/cdpm.cmake"
        "-DCDPM_PROJECT_CONFIG=${config}" "-DCDPM_STORE_DIR=${store}"
        "-DCMAKE_PREFIX_PATH=${tmp}/system/config" "-DCMAKE_MODULE_PATH=${tmp}/system/module"
        "-DCDPM_ALLOW_SYSTEM_PACKAGES=OFF"
        RESULT_VARIABLE rc OUTPUT_VARIABLE output ERROR_VARIABLE error)
    if(NOT rc EQUAL 0)
        message(FATAL_ERROR "FAIL: graph consumer configure failed\n${output}${error}")
    endif()
    file(READ "${tmp}/consumer/cdpm.lock.json" lock)
    string(JSON hash GET "${lock}" packages parent config_hash)
    set(${out_hash} "${hash}")
    return(PROPAGATE ${out_hash})
endfunction()

configure_consumer("${tmp}/build-one" first_hash)
file(READ "${tmp}/consumer/cdpm.lock.json" lock)
string(JSON package_count LENGTH "${lock}" packages)
assert_eq("${package_count}" 2 "provider lock contains managed graph")
string(JSON dependencies GET "${lock}" packages parent dependencies)
string(JSON dependency_count LENGTH "${dependencies}")
assert_eq("${dependency_count}" 1 "parent lock contains direct managed identity")
string(JSON systems GET "${lock}" packages parent system_dependencies)
string(JSON system_count LENGTH "${systems}")
assert_eq("${system_count}" 2 "parent lock contains system identities")

file(WRITE "${tmp}/system/fake-config.bin" "config-two")
configure_consumer("${tmp}/build-two" artifact_hash)
assert_ne("${artifact_hash}" "${first_hash}" "system artifact change moves parent hash")
file(APPEND "${tmp}/system/config/FakeConfigConfig.cmake" "# definition changed\n")
configure_consumer("${tmp}/build-three" definition_hash)
assert_ne("${definition_hash}" "${artifact_hash}" "system definition change moves parent hash")

# The real CLI uses the same resolver and records both graph nodes.
file(REMOVE "${tmp}/cdpm.lock.json")
execute_process(COMMAND "${CMAKE_COMMAND}" "-DCMAKE_PREFIX_PATH=${tmp}/system/config"
        "-DCMAKE_MODULE_PATH=${tmp}/system/module" "-DCDPM_STORE_DIR=${store}"
        "-DCDPM_RUNTIME_DIR=${tmp}/cli-runtime"
        -P "${cdpm_root}/cdpm-cli.cmake" --
        --project-dir "${tmp}" install ManagedParent
    RESULT_VARIABLE cli_rc OUTPUT_VARIABLE cli_output ERROR_VARIABLE cli_error)
if(NOT cli_rc EQUAL 0)
    message(FATAL_ERROR "FAIL: CLI graph install failed\n${cli_output}${cli_error}")
endif()
file(READ "${tmp}/cdpm.lock.json" cli_lock)
string(JSON cli_package_count LENGTH "${cli_lock}" packages)
assert_eq("${cli_package_count}" 2 "CLI install records the full graph")

# During replay, an undeclared nested request falls through to CMake's default find logic.
file(MAKE_DIRECTORY "${tmp}/bad-consumer")
file(WRITE "${tmp}/bad-consumer/CMakeLists.txt" [[cmake_minimum_required(VERSION 3.25)
project(bad_consumer NONE)
find_package(BadParent REQUIRED CONFIG)
]])
execute_process(COMMAND "${CMAKE_COMMAND}" -S "${tmp}/bad-consumer" -B "${tmp}/bad-build"
    "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cdpm_root}/cdpm.cmake"
    "-DCDPM_PROJECT_CONFIG=${config}" "-DCDPM_STORE_DIR=${store}" -DCDPM_ALLOW_SYSTEM_PACKAGES=ON
    RESULT_VARIABLE bad_rc OUTPUT_VARIABLE bad_output ERROR_VARIABLE bad_error)
if(bad_rc EQUAL 0)
    message(FATAL_ERROR "FAIL: undeclared replay dependency should have failed to be found\n${bad_output}${bad_error}")
endif()
if("${bad_output}${bad_error}" MATCHES "not declared in that package graph")
    message(FATAL_ERROR "FAIL: undeclared replay dependency was rejected by cdpm instead of falling through\n${bad_output}${bad_error}")
endif()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: provider and CLI resolve managed/system dependency graphs")
