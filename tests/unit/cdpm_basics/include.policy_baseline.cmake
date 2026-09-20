# Test: cdpm_basics pins its own policy baseline and leaves the includer's policy state untouched.
cmake_policy(VERSION 3.25...4.0)

# Intentional OLD setup: the module must not depend on the includer's policies.
set(CMAKE_WARN_DEPRECATED FALSE)
cmake_policy(SET CMP0140 OLD)
unset(CMAKE_WARN_DEPRECATED)

include(cdpm_basics)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# Under CMP0140 OLD return(PROPAGATE ...) would silently drop its arguments, leaving the output empty.
_cdpm_install_slot_dir("/store" "fmt" "0123456789abcdef" install_dir)
assert_eq("${install_dir}" "/store/fmt/0123456789abcdef" "module functions run on the module baseline")

cmake_policy(GET CMP0140 includer_state)
assert_eq("${includer_state}" "OLD" "the includer's policy state is not modified by the include")

message(STATUS "PASS: cdpm_basics policy baseline")
