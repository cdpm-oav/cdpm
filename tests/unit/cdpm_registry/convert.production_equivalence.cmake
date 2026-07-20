cmake_policy(SET CMP0053 NEW)

include(cdpm_registry_converter)
include(cdpm_hash)
include(cdpm_lockfile)
include(cdpm_cps)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

set(tmp "${CMAKE_CURRENT_LIST_DIR}/.tmp/convert_equivalence")
file(REMOVE_RECURSE "${tmp}")
file(MAKE_DIRECTORY "${tmp}/project/patches/alpha" "${tmp}/project/patches/beta")
file(WRITE "${tmp}/project/patches/alpha/shared.diff" "alpha shared patch\n")
file(WRITE "${tmp}/project/patches/alpha/only-alpha.diff" "alpha version-only patch\n")
file(WRITE "${tmp}/project/patches/beta/shared.diff" "beta shared patch\n")

set(alpha_pkg [[{
    "find_package_name": "Alpha",
    "build_system": "cmake",
    "source": {"type":"git","url":"https://example.test/alpha.git"},
    "default_version": "1.0.0",
    "version_schema": "simple",
    "options": {"ALPHA_OPT":"ON"},
    "version_options": [{"range":"[1.0.0->)","options":{"ALPHA_RANGE":"YES"}}],
    "patches": [{"file":"patches/alpha/shared.diff","applies_to":"[1.0.0->2.0.0)","exclude":["1.5.0"]}],
    "dependencies": {"beta":{"version":"2.0.0","components":["beta"]}},
    "system_dependencies": {"systemx":{"mode":"CONFIG","identity_targets":["SystemX::Core"],"identity_paths":["lib/systemx.lib"]}},
    "default_components": ["alpha"],
    "components": {"alpha":{"type":"interface"}},
    "versions": {"1.0.0":{"rev":"1111111111111111111111111111111111111111","patches":["patches/alpha/shared.diff","patches/alpha/only-alpha.diff"],"options":{"ALPHA_VER":"1"},"dependencies":{"beta":{"version":"2.0.0"}}}}
}]])

set(beta_pkg [[{
    "find_package_name": "Beta",
    "build_system": "cmake",
    "source": {"type":"git","url":"https://example.test/beta.git"},
    "default_version": "2.0.0",
    "options": {"BETA_OPT":"OFF"},
    "patches": [{"file":"patches/beta/shared.diff"}],
    "versions": {"2.0.0":{"rev":"2222222222222222222222222222222222222222","compat_version":"1.0.0"}}
}]])

file(WRITE "${tmp}/schema1.json" "{\"repo_schema\":1,\"packages\":{\"alpha\":${alpha_pkg},\"beta\":${beta_pkg}}}")

function(strip_patches meta out)
    set(result "${meta}")
    string(JSON patches_val ERROR_VARIABLE patches_err GET "${result}" patches)
    if(NOT patches_err)
        string(JSON removed REMOVE "${result}" patches)
        set(result "${removed}")
    endif()
    string(JSON versions_val ERROR_VARIABLE versions_err GET "${result}" versions)
    if(NOT versions_err)
        set(versions_updated "${versions_val}")
        _cdpm_json_foreach("${versions_updated}" vers)
        foreach(v IN LISTS vers)
            string(JSON vp_val ERROR_VARIABLE vp_err GET "${versions_updated}" "${v}" patches)
            if(NOT vp_err)
                string(JSON v_updated SET "${versions_updated}" "${v}" patches "[]")
                set(versions_updated "${v_updated}")
            endif()
        endforeach()
        string(JSON result2 SET "${result}" versions "${versions_updated}")
        set(result "${result2}")
    endif()
    cdpm_canonical_json("${result}" canonical)
    set(${out} "${canonical}" PARENT_SCOPE)
endfunction()

function(patch_sha_list pkg_key version meta out)
    cdpm_resolve_patch_list("${meta}" "${version}" list)
    string(JSON count ERROR_VARIABLE len_err LENGTH "${list}")
    set(shas "")
    if(NOT len_err AND count GREATER 0)
        math(EXPR last "${count} - 1")
        foreach(i RANGE 0 ${last})
            string(JSON authored GET "${list}" ${i})
            _cdpm_registry_resolve_patch_path("${pkg_key}" "${authored}" resolved)
            file(SHA256 "${resolved}" sha)
            list(APPEND shas "${sha}")
        endforeach()
    endif()
    set(${out} "${shas}" PARENT_SCOPE)
endfunction()

function(capture_package pkg_key version capture_name)
    cdpm_find_package_in_repo("${pkg_key}" found key meta)
    assert_true("${found}" "${capture_name}: canonical lookup")
    assert_eq("${key}" "${pkg_key}" "${capture_name}: canonical key")
    cdpm_resolve_version("${pkg_key}" "${meta}" "" version compat)
    cdpm_get_package_source("${pkg_key}" "${meta}" "${version}" source dev)
    cdpm_get_package_options("${pkg_key}" "${version}" options)
    cdpm_get_package_dependencies("${pkg_key}" "${meta}" "${version}" deps)
    cdpm_get_package_system_dependencies("${pkg_key}" "${meta}" "${version}" sysdeps)
    cdpm_compute_config_hash("${pkg_key}" "${version}" "${meta}" hash)
    patch_sha_list("${pkg_key}" "${version}" "${meta}" patch_shas)
    _cdpm_lockfile_compose_entry("${version}" "${hash}" "${source}" "${dev}"
        "${capture_name}_lock" DEPENDENCIES "${deps}" SYSTEM_IDENTITIES "${sysdeps}")
    _cdpm_cps_compose("${pkg_key}" "${version}" "${tmp}/store/${pkg_key}/${hash}" "${meta}" cps)
    strip_patches("${meta}" meta_stripped)
    set(${capture_name}_meta "${meta_stripped}" PARENT_SCOPE)
    set(${capture_name}_version "${version}" PARENT_SCOPE)
    set(${capture_name}_compat "${compat}" PARENT_SCOPE)
    set(${capture_name}_source "${source}" PARENT_SCOPE)
    set(${capture_name}_options "${options}" PARENT_SCOPE)
    set(${capture_name}_deps "${deps}" PARENT_SCOPE)
    set(${capture_name}_sysdeps "${sysdeps}" PARENT_SCOPE)
    set(${capture_name}_hash "${hash}" PARENT_SCOPE)
    set(${capture_name}_patch_shas "${patch_shas}" PARENT_SCOPE)
    set(${capture_name}_lock "${${capture_name}_lock}" PARENT_SCOPE)
    set(${capture_name}_cps "${cps}" PARENT_SCOPE)
endfunction()

# Load the original schema-1 registry via production path.
set(CDPM_PROJECT_DIR "${tmp}/project")
_cdpm_registry_reset()
cdpm_load_repo("${tmp}/schema1.json")
capture_package(alpha 1.0.0 s1_alpha)
capture_package(beta 2.0.0 s1_beta)

# Convert via the maintenance wrapper.
cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH unit_dir)
cmake_path(GET unit_dir PARENT_PATH tests_dir)
cmake_path(GET tests_dir PARENT_PATH cdpm_root)
set(wrapper "${cdpm_root}/tools/convert-registry-schema1-to-schema2.cmake")
execute_process(COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE=${tmp}/schema1.json" "-DDESTINATION=${tmp}/schema2"
        "-DPROJECT_DIR=${tmp}/project" -P "${wrapper}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
)
assert_eq("${result}" 0 "converter wrapper succeeds: ${output}${error}")
cdpm_validate_registry("${tmp}/schema2" valid diagnostics)
assert_true("${valid}" "generated schema-2 registry validates: ${diagnostics}")

# Load the generated schema-2 registry via production path.
set(CDPM_PROJECT_DIR "${tmp}/project")
_cdpm_registry_reset()
cdpm_load_repo("${tmp}/schema2/packages.json")
capture_package(alpha 1.0.0 s2_alpha)
capture_package(beta 2.0.0 s2_beta)

# Direct and alias lookups are equivalent.
cdpm_find_package_in_repo(Alpha alias_found alias_key alias_meta)
assert_true("${alias_found}" "schema-2 alias lookup finds Alpha")
assert_eq("${alias_key}" alpha "schema-2 alias lookup canonicalizes to alpha")
cdpm_find_package_in_repo(Beta beta_found beta_key beta_meta)
assert_true("${beta_found}" "schema-2 direct lookup finds beta")
assert_eq("${beta_key}" beta "schema-2 direct lookup key is beta")

# Canonical metadata is equivalent after normalizing representation-specific patch paths.
assert_json_eq("${s2_alpha_meta}" "${s1_alpha_meta}" "alpha canonical metadata is equivalent")
assert_json_eq("${s2_beta_meta}" "${s1_beta_meta}" "beta canonical metadata is equivalent")

# Resolved versions, sources, options, dependencies, and system deps are equivalent.
assert_eq("${s2_alpha_version}" "${s1_alpha_version}" "alpha resolved version")
assert_eq("${s2_alpha_compat}" "${s1_alpha_compat}" "alpha compat_version")
assert_json_eq("${s2_alpha_source}" "${s1_alpha_source}" "alpha source descriptor")
assert_json_eq("${s2_alpha_options}" "${s1_alpha_options}" "alpha effective options")
assert_json_eq("${s2_alpha_deps}" "${s1_alpha_deps}" "alpha dependencies")
assert_json_eq("${s2_alpha_sysdeps}" "${s1_alpha_sysdeps}" "alpha system dependencies")
assert_eq("${s2_beta_version}" "${s1_beta_version}" "beta resolved version")
assert_eq("${s2_beta_compat}" "${s1_beta_compat}" "beta compat_version")
assert_json_eq("${s2_beta_source}" "${s1_beta_source}" "beta source descriptor")
assert_json_eq("${s2_beta_options}" "${s1_beta_options}" "beta effective options")
assert_json_eq("${s2_beta_deps}" "${s1_beta_deps}" "beta dependencies")
assert_json_eq("${s2_beta_sysdeps}" "${s1_beta_sysdeps}" "beta system dependencies")

# Patch order and bytes are equivalent (only representation-specific paths differ).
assert_eq("${s2_alpha_patch_shas}" "${s1_alpha_patch_shas}" "alpha patch sha order")
assert_eq("${s2_beta_patch_shas}" "${s1_beta_patch_shas}" "beta patch sha order")

# Config hash, lock entry, and CPS output are equivalent.
assert_eq("${s2_alpha_hash}" "${s1_alpha_hash}" "alpha config hash")
assert_eq("${s2_beta_hash}" "${s1_beta_hash}" "beta config hash")
assert_json_eq("${s2_alpha_lock}" "${s1_alpha_lock}" "alpha lock entry")
assert_json_eq("${s2_beta_lock}" "${s1_beta_lock}" "beta lock entry")
assert_json_eq("${s2_alpha_cps}" "${s1_alpha_cps}" "alpha cps descriptor")
assert_json_eq("${s2_beta_cps}" "${s1_beta_cps}" "beta cps descriptor")

file(REMOVE_RECURSE "${tmp}")
message(STATUS "PASS: schema-1 and generated schema-2 are production-path equivalent")
