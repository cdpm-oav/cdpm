cmake_minimum_required(VERSION 3.25)

project(cdpm_tests)

option(CDPM_TEST_NETWORK "Enables network-required tests")

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
    cmake_parse_arguments(arg "" "" "PASS;NETWORK" ${ARGN})

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

    # NETWORK cases need internet + Git; registered only when CDPM_TEST_NETWORK is ON.
    if(CDPM_TEST_NETWORK)
        foreach(case IN LISTS arg_NETWORK)
            set(test_name "integration.${case}")
            add_test(NAME "${test_name}"
                COMMAND
                    "${CMAKE_COMMAND}"
                        -DCMAKE_MODULE_PATH=${cdpm_root}/core
                        -DCDPM_TEST_HELPERS=${CMAKE_CURRENT_SOURCE_DIR}
                        -P "${CMAKE_CURRENT_SOURCE_DIR}/integration/${case}.cmake"
                WORKING_DIRECTORY "${cdpm_root}"
            )
            set_tests_properties("${test_name}" PROPERTIES LABELS "integration;network")
        endforeach()
    endif()
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

add_unit_tests(MODULE cdpm_verange
    PASS
        parse.brackets
        parse.open_ends
        in_range.membership
        in_ranges.forms_and_excludes
    FAIL
        in_range.invalid_fatal
)

add_unit_tests(MODULE cdpm_hash
    PASS
        compute.deterministic
        compute.build_type_changes_hash
        compute.options_change_hash
        compute.compiler_version_changes_hash
        compute.patch_changes_hash
        compute.patch_applicability
        compute.toolchain_file_identity
        compute.toolchain_var_changes_hash
        compute.system_identities
        compute.dependency_identities
        compute.manifest_patch
        compute.host_profile
)

add_unit_tests(MODULE cdpm_toolchain
    PASS
        prepare.wrapper_includes_external
        prepare.freezes_allowlist
        prepare.synthesize
        prepare.host_native
)

add_unit_tests(MODULE cdpm_context
    PASS
        resolve.defaults
        resolve.overrides
)

add_unit_tests(MODULE cdpm_build
    PASS
        prepare_source.local
        collect_patches.absolute
        collect_patches.applies_to
        collect_patches.manifest_relative
        build.driver_validation_user_cleanup
        build.sentinel_skip
        build.autotools_configure_args
        build.host_context
        build.archive_cache_dir
    FAIL
        build.unimplemented_driver
)

add_unit_tests(MODULE cdpm_lockfile
    PASS
        write.creates_file
        write.url_source
        write.dev_override
        write.idempotent_merge
        read.missing_file
        read.roundtrip
        write.system_identities
        write.graph_identities
        write.local_is_dev
        read.structural_validation
    FAIL
        read.bad_json
)

add_unit_tests(MODULE cdpm_cps
    PASS
        generate.interface_basic
        generate.archive_location
        generate.compat_requires_platform
        generate.disabled_noop
)

add_integration_tests(
    PASS
        build_cmake_driver
        build_cmake_driver_security
        build_cmake_driver_patch
        build_cmake_driver_cps
        build_autotools_driver
        build_failure_user_cleanup
        cli_context
        cross_ios_simulator
        host_tool_graph
        provider_find_package
        provider_graph
        resolver_lock_modes
    NETWORK
        openssl_managed_perl_e2e
        provider_fmt_e2e
)

add_unit_tests(MODULE cdpm_config
    PASS
        add_registry.cli_command
        build_system.register_and_get
        canonical_json.sorts_keys
        config_blame.cli_command
        config_blame.layer_origins
        config_load.layer_merge
        config.build_system_override
        generate_user_file.basic
        get_package_options.layers
        get_package_system_dependencies.replacement
        get_package_dependencies.replacement
        get_package_host_dependencies.replacement
        host_dependencies.validation
        get_package_source.override_local
        get_package_source.repo_default
        get_package_user_kv.tracked_split
        load_repos.file_and_masks
        resolve_version.cache_override_skips_lockfile
        resolve_version.no_lockfile_flag_skips_lockfile
        url_template.version_underscored
        load_repos.force_resets_registry
        load_repos.git_local_baseline
        merge_json.deep
        merge_json.remove_operator
        pkg_matches_masks
    FAIL
        build_system.duplicate_no_override
        config_load.security.user_integrity
        config.build_system_override.unregistered
        generate_user_file.invalid_key
        get_package_source.override_without_flag
        get_package_source.override_wrong_type
        get_package_user_kv.missing_value
        load_repo.unknown_build_system
        load_repo.bad_version_range
        load_repo.invalid_option_key
        load_repo.invalid_rev
        load_repo.invalid_sha256
        load_repos.git_missing_baseline
        load_repos.unknown_kind
        load_repo.system_dependencies_bad_mode
        load_repo.system_dependencies_bad_type
        load_repo.system_dependencies_bad_targets
        load_repo.system_dependencies_bad_identity_paths
        load_repo.system_dependencies_overlap
        load_repo.system_dependencies_unsafe_name
        load_repo.system_dependencies_unknown_field
        load_repo.managed_dependencies_unknown_field
        load_repo.host_dependencies_invalid
        load_repo.duplicate_find_name
)

add_unit_tests(MODULE cdpm_registry
    PASS
        load.valid
        load.alias_canonical
        load.alias_deterministic_duplicate
        load.selective_direct
        load.masks_overlay
        load.repeated_masks
        load.root_index_fifo
        validate.api
        validate.cli
        load.malformed_index
        load.malformed_manifest
        load.manifest_traversal
    FAIL
        load.malformed_value
        load.key_mismatch
        load.case_collision
        load.manifest_absolute
        load.manifest_symlink_escape
        load.patch_absolute
        load.patch_traversal
        load.patch_missing
        load.patch_symlink_escape
        load.manifest_fifo
        load.patch_fifo
)
set_tests_properties(
    unit.cdpm_registry.load.manifest_symlink_escape
    unit.cdpm_registry.load.patch_symlink_escape
    unit.cdpm_registry.load.manifest_fifo
    unit.cdpm_registry.load.patch_fifo
    PROPERTIES SKIP_REGULAR_EXPRESSION "SKIP: symlink creation unsupported"
)
set_tests_properties(
    unit.cdpm_registry.load.manifest_fifo
    unit.cdpm_registry.load.patch_fifo
    unit.cdpm_registry.load.root_index_fifo
    PROPERTIES SKIP_REGULAR_EXPRESSION "SKIP: POSIX FIFO unavailable"
)

add_unit_tests(MODULE cdpm_system_dependencies
    PASS
        probe.config_and_module
    FAIL
        probe.missing_identity_path
        probe.symlink_identity_path
)

add_unit_tests(MODULE cdpm_resolve
    PASS
        resolve.shared_graph
        resolve.host_graph
    FAIL
        resolve.version_conflict
        resolve.cycle
        resolve.duplicate_alias
        resolve.host_rejects_target_dependency
)
set_tests_properties(unit.cdpm_system_dependencies.probe.symlink_identity_path
    PROPERTIES SKIP_REGULAR_EXPRESSION "SKIP: symlink creation unsupported"
)
