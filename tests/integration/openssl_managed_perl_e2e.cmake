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

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: openssl_managed_perl_e2e")
