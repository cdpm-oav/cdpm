# Test: build.driver_validation_user_cleanup
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/driver_validation_user_cleanup")

if(CHILD)
    cmake_policy(SET CMP0011 NEW)
    cmake_policy(SET CMP0140 NEW)
    include(cdpm_build)

    set(runtime "${tmp}/${CASE}/runtime")
    set(CDPM_STORE_DIR "${tmp}/${CASE}/store")
    set(CDPM_RUNTIME_DIR "${runtime}")
    set(CMAKE_BINARY_DIR "${tmp}/${CASE}/binary")
    file(MAKE_DIRECTORY "${tmp}/source")

    string(CONCAT effective
        "{\"allow_source_override\":true,\"user\":{"
        "\"example.secret\":{\"value\":\"top-secret\",\"tracked\":false}},"
        "\"packages\":{\"demo\":{\"source_override\":{\"type\":\"local\","
        "\"path\":\"${tmp}/source\"}}}}")
    set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "${effective}")

    if(CASE STREQUAL "missing")
        set(module "tests/unit/cdpm_build/.tmp/driver_validation_user_cleanup/missing.cmake")
        cdpm_register_build_system(missing "${module}")
    elseif(CASE STREQUAL "invalid")
        set(invalid_module "${tmp}/invalid.cmake")
        file(WRITE "${invalid_module}" "# Does not define the registered driver's build command.\n")
        set(module "tests/unit/cdpm_build/.tmp/driver_validation_user_cleanup/invalid.cmake")
        cdpm_register_build_system(invalid "${module}")
    endif()

    set(meta "{\"build_system\":\"${CASE}\",\"versions\":{\"1.0.0\":{}}}")
    cdpm_build_dependency(demo 1.0.0 validation "${meta}")
    message(FATAL_ERROR "UNREACHABLE: driver '${CASE}' did not abort")
endif()

file(REMOVE_RECURSE "${tmp}")
foreach(case IN ITEMS unknown missing invalid autotools)
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -DCHILD=ON -DCASE=${case} -DCDPM_TEST_HELPERS=${CDPM_TEST_HELPERS}
            -DCMAKE_MODULE_PATH=${CMAKE_MODULE_PATH} -P "${CMAKE_CURRENT_LIST_FILE}"
        RESULT_VARIABLE rc
        OUTPUT_VARIABLE stdout
        ERROR_VARIABLE stderr
    )
    if(rc EQUAL 0)
        message(FATAL_ERROR "FAIL: driver '${case}' unexpectedly succeeded")
    endif()
    if(case STREQUAL "unknown")
        set(expected "unknown build_system 'unknown'")
    elseif(case STREQUAL "missing")
        set(expected "build-system driver module not found")
    elseif(case STREQUAL "invalid")
        set(expected "driver 'invalid' did not define")
    else()
        set(expected "driver 'autotools' is not yet implemented")
    endif()
    assert_match("${stdout}${stderr}" "${expected}" "driver '${case}' reached its expected failure")
    if(EXISTS "${tmp}/${case}/runtime/user/demo-validation.cmake")
        message(FATAL_ERROR "FAIL: driver '${case}' left its generated user file")
    endif()
    if(case MATCHES "^(unknown|missing|invalid)$" AND EXISTS "${tmp}/${case}/runtime/user")
        message(FATAL_ERROR "FAIL: driver '${case}' generated a user file before validation")
    endif()
    if(case STREQUAL "autotools" AND NOT EXISTS "${tmp}/${case}/runtime/user")
        message(FATAL_ERROR "FAIL: stub driver was not reached after user file generation")
    endif()
endforeach()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: driver validation failures cannot leave user files and stubs clean them up")
