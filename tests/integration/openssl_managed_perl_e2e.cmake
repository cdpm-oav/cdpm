# Integration: openssl_managed_perl_e2e (NETWORK)
#
# End-to-end proof that OpenSSL consumes a cdpm-managed Perl host dependency.
# Using the real cdpm-repo registry, cdpm_resolve_and_build(openssl) resolves Perl
# as a HOST node, builds it from the archive into the store, then builds OpenSSL as
# a TARGET node. The OpenSSL driver searches for perl only in the host program path,
# so a successful build demonstrates that managed Perl (not system PATH) was used.
include(cdpm_resolve)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)
cmake_path(GET cdpm_root PARENT_PATH workspace_root)

set(registry "${workspace_root}/cdpm-repo/packages.json")
if(NOT EXISTS "${registry}")
    message(FATAL_ERROR "FAIL: real registry not found at ${registry} (is cdpm-repo checked out?)")
endif()

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/openssl_managed_perl_e2e")
# A previous run may have left a read-only Perl install behind (Perl installs read-only
# directories). Make the leftover writable before removing it, otherwise the stale tree
# survives file(REMOVE_RECURSE) and poisons this run with extra store slots.
if(EXISTS "${tmp}" AND UNIX)
    execute_process(COMMAND chmod -R u+w "${tmp}" TIMEOUT 60)
endif()
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/project")

set(project_dir "${tmp}/project")
set(CDPM_PROJECT_DIR "${project_dir}")
set(CDPM_STORE_DIR "${tmp}/store")
set(CDPM_RUNTIME_DIR "${tmp}/runtime")

# ---- Project config: real registry, pin OpenSSL to a known version ------------
file(WRITE "${project_dir}/cdpm.json" "{")
file(APPEND "${project_dir}/cdpm.json" "\n  \"repos\": [ { \"kind\": \"file\", \"path\": \"${registry}\" } ],")
file(APPEND "${project_dir}/cdpm.json" "\n  \"packages\": { \"openssl\": { \"version\": \"3.0.21\" } }")
file(APPEND "${project_dir}/cdpm.json" "\n}")

# ---- Canonicalize host build flags for script-mode hashing --------------------
# The consumer configure runs inside a real project where cdpm.cmake probes C via
# check_language. This test runs as cmake -P (script mode), so CMAKE_C_COMPILER and
# CMAKE_OSX_SYSROOT are not populated. Probe them once in a disposable project so
# the HOST hash computed here matches the one computed during consumer configure,
# and so the OpenSSL driver receives a valid SDKROOT on Apple hosts.
set(_cc_probe_dir "${tmp}/_cc_probe")
set(_cc_probe_build "${tmp}/_cc_probe-build")
file(MAKE_DIRECTORY "${_cc_probe_dir}")
file(WRITE "${_cc_probe_dir}/CMakeLists.txt"
    "cmake_minimum_required(VERSION 3.25)\n"
    "project(_cc_probe LANGUAGES C)\n"
    "file(WRITE \"${tmp}/host_cc.txt\" \"\${CMAKE_C_COMPILER}\")\n"
    "file(WRITE \"${tmp}/host_sysroot.txt\" \"\${CMAKE_OSX_SYSROOT}\")\n")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -S "${_cc_probe_dir}" -B "${_cc_probe_build}"
    RESULT_VARIABLE _cc_rc
)
if(NOT _cc_rc EQUAL 0)
    message(FATAL_ERROR "FAIL: host C compiler probe failed (rc=${_cc_rc})")
endif()
file(READ "${tmp}/host_cc.txt" CMAKE_C_COMPILER)
string(STRIP "${CMAKE_C_COMPILER}" CMAKE_C_COMPILER)
if(NOT EXISTS "${CMAKE_C_COMPILER}")
    message(FATAL_ERROR "FAIL: probed host C compiler does not exist: ${CMAKE_C_COMPILER}")
endif()
file(READ "${tmp}/host_sysroot.txt" CMAKE_OSX_SYSROOT)
string(STRIP "${CMAKE_OSX_SYSROOT}" CMAKE_OSX_SYSROOT)

# ---- Resolve and build OpenSSL (this pulls in Perl as a host dependency) ------
cdpm_resolve_and_build(openssl "" context)

# ---- Context checks: Perl is HOST, OpenSSL is TARGET --------------------------
string(JSON host_managed_len LENGTH "${context}" host_managed)
string(JSON managed_len LENGTH "${context}" managed)
assert_eq("${host_managed_len}" 1 "Perl is the single host node")
assert_eq("${managed_len}" 1 "OpenSSL is the single target node")

string(JSON perl_record GET "${context}" host_managed perl)
string(JSON openssl_record GET "${context}" managed openssl)

string(JSON host_prefix_len LENGTH "${context}" host_prefixes)
assert_eq("${host_prefix_len}" 1 "exactly one host prefix is exposed")
string(JSON perl_prefix GET "${context}" host_prefixes 0)

# ---- Lockfile records both sections ------------------------------------------
file(READ "${project_dir}/cdpm.lock.json" lock)
string(JSON host_packages_len LENGTH "${lock}" host_packages)
string(JSON packages_len LENGTH "${lock}" packages)
assert_eq("${host_packages_len}" 1 "lockfile host_packages section records Perl")
assert_eq("${packages_len}" 1 "lockfile packages section records OpenSSL")

string(JSON openssl_host_deps GET "${lock}" packages openssl host_dependencies)
string(JSON perl_identity GET "${openssl_host_deps}" perl)
string(JSON perl_identity_package GET "${perl_identity}" package)
assert_eq("${perl_identity_package}" "perl" "OpenSSL lock entry records Perl host dependency")

# ---- The managed Perl interpreter exists in the store -------------------------
string(JSON perl_install_dir GET "${perl_record}" install_dir)
if(NOT EXISTS "${perl_install_dir}/bin/perl")
    message(FATAL_ERROR "FAIL: managed Perl was not installed at ${perl_install_dir}/bin/perl")
endif()

# ---- OpenSSL is installed in the store ----------------------------------------
string(JSON openssl_install_dir GET "${openssl_record}" install_dir)
if(NOT EXISTS "${openssl_install_dir}/.cdpm_installed")
    message(FATAL_ERROR "FAIL: OpenSSL was not installed at ${openssl_install_dir}")
endif()

# ---- Fixture marker: the OpenSSL driver embedded the store perl into its EP ---
# The driver resolves perl_exe with find_program(... PATHS ${program_path} NO_DEFAULT_PATH)
# and bakes the literal path into the generated mini-project. Inspect that file
# to prove the store perl was used rather than anything on the host PATH.
string(JSON openssl_hash GET "${openssl_record}" config_hash)
set(openssl_ep "${CDPM_RUNTIME_DIR}/bs/openssl-${openssl_hash}/_cdpm_ep/CMakeLists.txt")
if(NOT EXISTS "${openssl_ep}")
    message(FATAL_ERROR "FAIL: OpenSSL mini-project was not generated at ${openssl_ep}")
endif()
file(READ "${openssl_ep}" ep_content)
if(NOT "${ep_content}" MATCHES "${perl_install_dir}/bin/perl")
    message(FATAL_ERROR "FAIL: OpenSSL mini-project did not reference the managed Perl path "
        "(${perl_install_dir}/bin/perl)\nmini-project content:\n${ep_content}")
endif()

# Reject the common system perl paths to be extra explicit about PATH isolation.
if("${ep_content}" MATCHES "/usr/bin/perl" OR "${ep_content}" MATCHES "/usr/local/bin/perl")
    message(FATAL_ERROR "FAIL: OpenSSL mini-project appears to reference a system Perl")
endif()

# ---- Store-slot convergence: one Perl (HOST) and one OpenSSL slot ---------------
function(_count_installed_slots pkg_dir out_count)
    set(count 0)
    file(GLOB hash_dirs LIST_DIRECTORIES true "${pkg_dir}/*")
    foreach(hash_dir IN LISTS hash_dirs)
        if(IS_DIRECTORY "${hash_dir}" AND EXISTS "${hash_dir}/.cdpm_installed")
            math(EXPR count "${count} + 1")
        endif()
    endforeach()
    set(${out_count} "${count}" PARENT_SCOPE)
endfunction()

_count_installed_slots("${CDPM_STORE_DIR}/perl" perl_slot_count)
_count_installed_slots("${CDPM_STORE_DIR}/openssl" openssl_slot_count)
assert_eq("${perl_slot_count}" 1 "exactly one Perl store slot exists (HOST)")
assert_eq("${openssl_slot_count}" 1 "exactly one OpenSSL store slot exists")

# ---- FindPerl-style lookup resolves via PERL_EXECUTABLE hint --------------------
set(perl_consumer_dir "${tmp}/perl_consumer")
file(MAKE_DIRECTORY "${perl_consumer_dir}")
file(WRITE "${perl_consumer_dir}/CMakeLists.txt"
    "cmake_minimum_required(VERSION 3.25)\n"
    "project(perl_consumer LANGUAGES NONE)\n"
    "find_package(Perl REQUIRED)\n"
    "file(WRITE \"\${CMAKE_CURRENT_BINARY_DIR}/perl_exe.txt\" \"\${PERL_EXECUTABLE}\")\n")

set(perl_consumer_build "${tmp}/perl_consumer-build")
set(gen_args "")
if(DEFINED CMAKE_GENERATOR AND NOT CMAKE_GENERATOR STREQUAL "")
    set(gen_args -G "${CMAKE_GENERATOR}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -S "${perl_consumer_dir}"
        -B "${perl_consumer_build}"
        ${gen_args}
        "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${cdpm_root}/cdpm.cmake"
        "-DCDPM_STORE_DIR=${CDPM_STORE_DIR}"
        "-DCDPM_PROJECT_CONFIG=${project_dir}/cdpm.json"
        "-DCMAKE_BUILD_TYPE=Release"
    RESULT_VARIABLE perl_rc
    OUTPUT_VARIABLE perl_out
    ERROR_VARIABLE perl_err
)
if(NOT perl_rc EQUAL 0)
    message(FATAL_ERROR "FAIL: find_package(Perl) consumer configure failed (rc=${perl_rc})\n"
        "${perl_out}\n${perl_err}")
endif()

file(READ "${perl_consumer_build}/perl_exe.txt" found_perl)
string(STRIP "${found_perl}" found_perl)
assert_eq("${found_perl}" "${perl_install_dir}/bin/perl"
    "FindPerl resolved PERL_EXECUTABLE to the managed Perl")

# The consumer must reuse the existing Perl slot, not create a target-mode Perl.
_count_installed_slots("${CDPM_STORE_DIR}/perl" perl_slot_count_after)
assert_eq("${perl_slot_count_after}" 1 "find_package(Perl) did not create an additional Perl slot")

# Perl installs read-only directories that file(REMOVE_RECURSE) cannot remove on its own.
if(UNIX)
    execute_process(COMMAND chmod -R +w "${tmp}" TIMEOUT 30)
endif()
file(REMOVE_RECURSE "${tmp}" "${perl_consumer_build}")
message(STATUS "PASS: openssl_managed_perl_e2e")
