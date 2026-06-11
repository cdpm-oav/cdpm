
macro(assert_eq actual expected msg)
    if(NOT "${actual}" STREQUAL "${expected}")
        message(FATAL_ERROR "FAIL: ${msg}\n  expected: '${expected}'\n  got:      '${actual}'")
    endif()
endmacro()

macro(assert_empty val msg)
    if(NOT "${val}" STREQUAL "")
        message(FATAL_ERROR "FAIL: ${msg}\n  expected empty, got: '${val}'")
    endif()
endmacro()
