cmake_minimum_required(VERSION 3.25)

project(cdpm_tests)

enable_testing()

# add_test(NAME "unit.**"
#     COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_SOURCE_DIR}/unit/**.cmake"
#     WORKING_DIRECTORY "$<PATH:CMAKE_PATH,NORMALIZE,${CMAKE_SOURCE_DIR}/../>"
# )

# TODO: make function to register tests by module + pass/fail cases

# cdpm_uri tests
block(SCOPE_FOR VARIABLES)
    set(module_name cdpm_uri)

    list(APPEND pass_tests
        parse_uri.shortcut.gh_basic
        parse_uri.shortcut.gh_with_ref
        parse_uri.shortcut.gh_ref_subdir
        parse_uri.shortcut.case_insensitive
        parse_uri.shortcut.all_builtins
        parse_uri.shortcut.custom
        parse_uri.https.git_repo
        parse_uri.https.archive
        parse_uri.https.unknown
        parse_uri.ssh
        parse_uri.file
        parse_uri.plain.scp_style
        parse_uri.plain.local_path
        parse_uri.register.duplicate_quiet
        parse_uri.register.override
        parse_uri.register.override_builtin
    )

    list(APPEND fail_tests
        parse_uri.register.duplicate_fatal
        parse_uri.register.missing_path_placeholder
    )

    foreach(unit_name IN LISTS pass_tests fail_tests)
        add_test(NAME "unit.${module_name}.${unit_name}"
            COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_SOURCE_DIR}/unit/${module_name}/${unit_name}.cmake"
            WORKING_DIRECTORY "$<PATH:CMAKE_PATH,NORMALIZE,${CMAKE_SOURCE_DIR}/../>"
        )
    endforeach()

    foreach(unit_name IN LISTS fail_tests)
        set_tests_properties("unit.${module_name}.${unit_name}" 
            PROPERTIES
                WILL_FAIL TRUE
        )
    endforeach()

endblock()
