cmake_minimum_required(VERSION 3.25)

project(cdpm_tests)

enable_testing()

# add_test(NAME "unit.**"
#     COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_SOURCE_DIR}/unit/**.cmake"
#     WORKING_DIRECTORY "$<PATH:CMAKE_PATH,NORMALIZE,${CMAKE_SOURCE_DIR}/../>"
# )

function(add_unit_tests)
    cmake_parse_arguments(arg "" "MODULE" "PASS;FAIL" ${ARGN})

    cmake_path(GET CMAKE_CURRENT_SOURCE_DIR PARENT_PATH cdpm_root)

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
