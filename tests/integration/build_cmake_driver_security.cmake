# Integration: generated CMake mini-project values cannot inject commands or change during parsing.
include(cdpm_build)
include(bs/cdpm_bs_cmake)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/build_cmake_driver_security")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}")

# Exercise source, patch, install/cache paths and option values containing CMake-significant text.
set(source "${tmp}/source-)message(FATAL_ERROR-CDPM_SOURCE_INJECTED)-pipe|")
file(MAKE_DIRECTORY "${source}")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/fixtures/greet/" DESTINATION "${source}")
set(patch "${tmp}/patch-)message(FATAL_ERROR-CDPM_PATCH_INJECTED)-pipe|.patch")
file(WRITE "${patch}"
    "--- a/include/greet.hpp\n+++ b/include/greet.hpp\n@@ -1,3 +1,3 @@\n // Filler header for test\n #pragma once\n"
    "-inline const char* greet(){ return \"hello from greet\"; }\n"
    "+inline const char* greet(){ return \"secure greeting\"; }\n")

set(roundtrip
    [=[value with spaces;list item|pipe\backslash;${CMAKE_CURRENT_LIST_DIR};$ENV{HOME};") message(FATAL_ERROR CDPM_INJECTED) #]=]
)
set(option_json "{}")
_cdpm_json_set_safe("${option_json}" CDPM_ROUNDTRIP "${roundtrip}" STRING option_json)

set(source_json "{}")
_cdpm_json_set_safe("${source_json}" type local STRING source_json)
_cdpm_json_set_safe("${source_json}" path "${source}" STRING source_json)
set(patches "[]")
string(JSON patches SET "${patches}" 0 "\"${patch}\"")
set(ctx "{}")
_cdpm_json_set_safe("${ctx}" build_dir "${tmp}/build-pipe|" STRING ctx)
_cdpm_json_set_safe("${ctx}" install_dir "${tmp}/install-pipe|" STRING ctx)
_cdpm_json_set_safe("${ctx}" ep_target "cdpm_pkg_security_test" STRING ctx)
_cdpm_json_set_safe("${ctx}" source "${source_json}" OBJECT ctx)
_cdpm_json_set_safe("${ctx}" patches "${patches}" ARRAY ctx)
_cdpm_json_set_safe("${ctx}" options "${option_json}" OBJECT ctx)
_cdpm_json_set_safe("${ctx}" build_type Release STRING ctx)
_cdpm_json_set_safe("${ctx}" generator "" STRING ctx)
_cdpm_json_set_safe("${ctx}" prefix_path "${tmp}/prefix-a;${tmp}/prefix|b" STRING ctx)
_cdpm_json_set_safe("${ctx}" module_path "${CMAKE_MODULE_PATH}" STRING ctx)
_cdpm_json_set_safe("${ctx}" toolchain "" STRING ctx)
_cdpm_json_set_safe("${ctx}" user_file "" STRING ctx)
string(JSON ctx_options GET "${ctx}" options)
assert_json_member("${ctx_options}" CDPM_ROUNDTRIP "${roundtrip}" "security option reaches driver context")
cdpm_bs_cmake_build("${ctx}")

string(JSON install_dir GET "${ctx}" install_dir)
file(READ "${install_dir}/roundtrip.txt" actual)
assert_eq("${actual}" "${roundtrip}" "CMake-significant option text round-trips through cache args")
file(READ "${install_dir}/include/greet.hpp" installed_header)
assert_match("${installed_header}" "secure greeting" "special-character patch path is applied")

# Newlines are rejected before a generated project can parse the payload.
set(newline_script "${tmp}/newline.cmake")
set(newline_marker "${tmp}/newline-marker")
file(WRITE "${newline_script}"
    "include(bs/cdpm_bs_cmake)\nset(value [=[bad\n)\nfile(WRITE \"${newline_marker}\" injected)\n]=])\n"
    "_cdpm_cmake_quote_argument(\"\${value}\" out)\n")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -DCMAKE_MODULE_PATH=${CMAKE_MODULE_PATH} -P "${newline_script}"
    RESULT_VARIABLE newline_rc
    OUTPUT_VARIABLE newline_out
    ERROR_VARIABLE newline_err
)
if(newline_rc EQUAL 0 OR NOT "${newline_out}${newline_err}" MATCHES "unsupported control")
    message(FATAL_ERROR "FAIL: newline payload was not rejected safely\n${newline_out}${newline_err}")
endif()
if(EXISTS "${newline_marker}")
    message(FATAL_ERROR "FAIL: newline payload executed its injected command")
endif()

# Values that ExternalProject re-embeds in its own scripts reject syntax-significant characters.
set(external_script "${tmp}/external-value.cmake")
set(external_marker "${tmp}/external-marker")
file(WRITE "${external_script}"
    "include(bs/cdpm_bs_cmake)\nset(value [=[bad\") file(WRITE \"${external_marker}\" injected) #]=])\n"
    "_cdpm_cmake_quote_external_project_value(\"\${value}\" out)\n")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -DCMAKE_MODULE_PATH=${CMAKE_MODULE_PATH} -P "${external_script}"
    RESULT_VARIABLE external_rc
    OUTPUT_VARIABLE external_out
    ERROR_VARIABLE external_err
)
if(external_rc EQUAL 0 OR NOT "${external_out}${external_err}" MATCHES "unsupported")
    message(FATAL_ERROR "FAIL: unsafe ExternalProject value was not rejected\n${external_out}${external_err}")
endif()
if(EXISTS "${external_marker}")
    message(FATAL_ERROR "FAIL: ExternalProject value executed its injected command")
endif()

# Closing bracket delimiters are rejected before ExternalProject can re-embed source/patch or cache values
# through cmake_language(EVAL).
foreach(value_kind source patch cache)
    set(delimiter_script "${tmp}/${value_kind}-closing-delimiter.cmake")
    set(delimiter_marker "${tmp}/${value_kind}-closing-delimiter-marker")
    set(delimiter_payload "bad]===]) file(WRITE \"${delimiter_marker}\" injected) #")
    _cdpm_cmake_quote_argument("${delimiter_payload}" delimiter_payload_q)
    file(WRITE "${delimiter_script}"
        "include(bs/cdpm_bs_cmake)\n"
        "set(value ${delimiter_payload_q})\n")
    if(value_kind STREQUAL "cache")
        file(APPEND "${delimiter_script}" "_cdpm_cmake_quote_cache_argument(\"\${value}\" SEP out)\n")
    else()
        file(APPEND "${delimiter_script}" "_cdpm_cmake_quote_external_project_value(\"\${value}\" out)\n")
    endif()
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -DCMAKE_MODULE_PATH=${CMAKE_MODULE_PATH} -P "${delimiter_script}"
        RESULT_VARIABLE delimiter_rc
        OUTPUT_VARIABLE delimiter_out
        ERROR_VARIABLE delimiter_err
    )
    if(delimiter_rc EQUAL 0 OR NOT "${delimiter_out}${delimiter_err}" MATCHES "unsupported closing")
        message(FATAL_ERROR "FAIL: ${value_kind} closing delimiter was not rejected safely\n"
            "${delimiter_out}${delimiter_err}")
    endif()
    if(EXISTS "${delimiter_marker}")
        message(FATAL_ERROR "FAIL: ${value_kind} closing-delimiter payload executed")
    endif()
endforeach()

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: generated mini-project arguments are safely serialized")
