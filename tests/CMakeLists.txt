cmake_minimum_required(VERSION 3.25)

project(cdpm_tests)

enable_testing()

# Get core root path
cmake_path(GET CMAKE_CURRENT_SOURCE_DIR PARENT_PATH cdpm_root)

function(add_unit_tests)
    cmake_parse_arguments(arg "" "MODULE" "PASS;FAIL" ${ARGN})

    foreach(case IN LISTS arg_PASS arg_FAIL)
        set(unit_name "unit.${arg_MODULE}.${case}")
        add_test(NAME "${unit_name}"
            COMMAND 
                "${CMAKE_COMMAND}" 
                    -DCMAKE_MODULE_PATH=${cdpm_root}/core
                    -DCDPM_TEST_HELPERS=${CMAKE_CURRENT_SOURCE_DIR}
                    -P "${CMAKE_CURRENT_SOURCE_DIR}/unit/${arg_MODULE}/${case}.cmake"
            WORKING_DIRECTORY "${cdpm_root}"
        )
        set_tests_properties("${unit_name}" 
            PROPERTIES 
                LABELS "${arg_MODULE}"
        )
    endforeach()

    foreach(case IN LISTS arg_FAIL)
        set_tests_properties("unit.${arg_MODULE}.${case}"
            PROPERTIES 
                WILL_FAIL TRUE
        )
    endforeach()
endfunction()

function(add_integration_tests)
    cmake_parse_arguments(arg "" "" "PASS" ${ARGN})

    foreach(case IN LISTS arg_PASS)
        set(test_name "integration.${case}")
        add_test(NAME "${test_name}"
            COMMAND
                "${CMAKE_COMMAND}"
                    -DCMAKE_MODULE_PATH=${cdpm_root}/core
                    -DCDPM_TEST_HELPERS=${CMAKE_CURRENT_SOURCE_DIR}
                    -P "${CMAKE_CURRENT_SOURCE_DIR}/integration/${case}.cmake"
            WORKING_DIRECTORY "${cdpm_root}"
        )
        set_tests_properties("${test_name}" PROPERTIES LABELS "integration")
    endforeach()
endfunction()

# cdpm_uri tests
add_unit_tests(
    MODULE cdpm_uri
    PASS
        parse_uri.file
        parse_uri.https.archive
        parse_uri.https.git_repo
        parse_uri.https.unknown
        parse_uri.plain.local_path
        parse_uri.plain.scp_style
        parse_uri.register.duplicate_quiet
        parse_uri.register.override
        parse_uri.register.override_builtin
        parse_uri.shortcut.all_builtins
        parse_uri.shortcut.case_insensitive
        parse_uri.shortcut.custom
        parse_uri.shortcut.gh_basic
        parse_uri.shortcut.gh_ref_subdir
        parse_uri.shortcut.gh_with_ref
        parse_uri.ssh
    FAIL
        parse_uri.register.duplicate_fatal
        parse_uri.register.missing_path_placeholder
)

add_unit_tests(MODULE cdpm_version
    PASS
        get_version.from_file
        get_version.strips_whitespace
        get_version.semver_with_prerelease
        get_version.semver_with_build_metadata
        get_version.missing_file_fallback
        get_version.empty_file_fallback
        get_version.non_semver_used_as_is
        get_version.cache_persists
)

add_unit_tests(MODULE cdpm_hash
    PASS
        compute.deterministic
        compute.build_type_changes_hash
        compute.options_change_hash
        compute.compiler_version_changes_hash
        compute.patch_changes_hash
        compute.toolchain_var_changes_hash
)

add_unit_tests(MODULE cdpm_toolchain
    PASS
        prepare.wrapper_includes_external
        prepare.freezes_allowlist
        prepare.synthesize
)

add_unit_tests(MODULE cdpm_build
    PASS
        prepare_source.local
        collect_patches.absolute
        build.sentinel_skip
    FAIL
        build.unimplemented_driver
)

add_integration_tests(
    PASS
        build_cmake_driver
        build_cmake_driver_patch
)

add_unit_tests(MODULE cdpm_config
    PASS
        build_system.register_and_get
        canonical_json.sorts_keys
        config_blame.cli_command
        config_blame.layer_origins
        config_load.layer_merge
        generate_user_file.basic
        get_package_source.override_local
        get_package_source.repo_default
        get_package_user_kv.tracked_split
        load_repos.file_and_masks
        merge_json.deep
        merge_json.remove_operator
        pkg_matches_masks
    FAIL
        build_system.duplicate_no_override
        config_load.security.user_integrity
        generate_user_file.invalid_key
        get_package_source.override_without_flag
        get_package_source.override_wrong_type
        get_package_user_kv.missing_value
        load_repo.unknown_build_system
        load_repos.git_missing_baseline
        load_repos.unknown_kind
)
