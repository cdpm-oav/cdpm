

# .. rst:
# ``assert_eq(<actual> <expected> <what>)`` - string equality.
function(assert_eq actual expected what)
    if(NOT "${actual}" STREQUAL "${expected}")
        message(FATAL_ERROR "FAIL: ${what}\n  expected: '${expected}'\n  actual:   '${actual}'")
    endif()
endfunction()

# .. rst:
# ``assert_ne(<actual> <unexpected> <what>)`` - string inequality.
function(assert_ne actual unexpected what)
    if("${actual}" STREQUAL "${unexpected}")
        message(FATAL_ERROR "FAIL: ${what}\n  did not expect: '${unexpected}'")
    endif()
endfunction()

# .. rst:
# ``assert_true(<value> <what>)`` - CMake truthiness.
function(assert_true value what)
    if(NOT value)
        message(FATAL_ERROR "FAIL: ${what}\n  expected a truthy value, got: '${value}'")
    endif()
endfunction()

# .. rst:
# ``assert_false(<value> <what>)`` - CMake falsiness.
function(assert_false value what)
    if(value)
        message(FATAL_ERROR "FAIL: ${what}\n  expected a falsy value, got: '${value}'")
    endif()
endfunction()

# .. rst:
# ``assert_match(<text> <regex> <what>)`` - regex match.
function(assert_match text regex what)
    if(NOT "${text}" MATCHES "${regex}")
        message(FATAL_ERROR "FAIL: ${what}\n  text did not match /${regex}/:\n  '${text}'")
    endif()
endfunction()

# .. rst:
# ``assert_empty(<val> <what>)`` - value emptiness.
macro(assert_empty val what)
    if(NOT "${val}" STREQUAL "")
        message(FATAL_ERROR "FAIL: ${what}\n  expected empty, got: '${val}'")
    endif()
endmacro()

# .. rst:
# ``assert_json_eq(<actual_json> <expected_json> <what>)`` - semantic JSON equality
# (key order / whitespace insensitive) via string(JSON ... EQUAL).
function(assert_json_eq actual expected what)
    string(JSON eq ERROR_VARIABLE err EQUAL "${actual}" "${expected}")
    if(err OR NOT eq)
        message(FATAL_ERROR "FAIL: ${what}\n  expected JSON: '${expected}'\n  actual JSON:   '${actual}'")
    endif()
endfunction()

# .. rst:
# ``assert_json_member(<json> <key> <expected> <what>)`` - a top-level member equals a scalar 
# (uses GET, which unwraps scalars on the 3.25 baseline).
function(assert_json_member json key expected what)
    string(JSON val ERROR_VARIABLE err GET "${json}" "${key}")
    if(err)
        message(FATAL_ERROR "FAIL: ${what}\n  member '${key}' not found in: '${json}'")
    endif()
    if(NOT "${val}" STREQUAL "${expected}")
        message(FATAL_ERROR "FAIL: ${what}\n  ${key}: expected '${expected}', actual '${val}'")
    endif()
endfunction()
