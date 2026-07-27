# cdpm_bs_common.cmake - Shared utilities for cdpm non-CMake build-system drivers.

include_guard(GLOBAL)

cmake_policy(SET CMP0140 NEW)

# .. rst:
# ``_cdpm_bs_validate_external_project_value(<str>)``
#
# ExternalProject re-embeds values in bracket arguments through ``cmake_language(EVAL)``. Reject any
# possible closing bracket delimiter before handing a value to it.
function(_cdpm_bs_validate_external_project_value str)
    if(str MATCHES [=[\]=*\]]=])
        message(FATAL_ERROR "[cdpm] ExternalProject value contains an unsupported closing delimiter.")
    endif()
endfunction()

# .. rst:
# ``_cdpm_bs_quote_argument(<str> <out_var>)``
#
# Serializes one string as a quoted CMake argument for a generated mini-project. CMake cannot safely
# represent control characters there, so reject them rather than allowing a value to alter its syntax.
function(_cdpm_bs_quote_argument str out)
    foreach(code RANGE 1 31)
        string(ASCII ${code} control)
        string(FIND "${str}" "${control}" control_index)
        if(NOT control_index EQUAL -1)
            message(FATAL_ERROR "[cdpm] generated argument contains an unsupported control character.")
        endif()
    endforeach()
    string(ASCII 127 control)
    string(FIND "${str}" "${control}" control_index)
    if(NOT control_index EQUAL -1)
        message(FATAL_ERROR "[cdpm] generated argument contains an unsupported control character.")
    endif()
    string(REPLACE "\\" "\\\\" escaped "${str}")
    string(REPLACE "$" "\\$" escaped "${escaped}")
    string(REPLACE "\"" "\\\"" escaped "${escaped}")
    string(REPLACE ";" "\\;" escaped "${escaped}")
    set(${out} "\"${escaped}\"")
    return(PROPAGATE ${out})
endfunction()

# .. rst:
# ``_cdpm_bs_quote_external_project_value(<str> <out_var>)``
#
# Serializes source and command values that ExternalProject embeds again in generated scripts.
function(_cdpm_bs_quote_external_project_value str out)
    _cdpm_bs_validate_external_project_value("${str}")
    foreach(unsupported IN ITEMS "$" ";" "\"")
        string(FIND "${str}" "${unsupported}" unsupported_index)
        if(NOT unsupported_index EQUAL -1)
            message(FATAL_ERROR "[cdpm] ExternalProject value contains an unsupported character.")
        endif()
    endforeach()
    _cdpm_bs_quote_argument("${str}" quoted)
    set(${out} "${quoted}")
    return(PROPAGATE ${out})
endfunction()

# .. rst:
# ``_cdpm_bs_download_lines(<source_json> <out_var>)``
#
# Generates an ExternalProject download block for a source object of type ``git``, ``url``, or
# ``local``. The returned lines are indented for direct inclusion in ``ExternalProject_Add``.
function(_cdpm_bs_download_lines source_json out)
    string(JSON src_type GET "${source_json}" "type")

    if(src_type STREQUAL "git")
        string(JSON url GET "${source_json}" "url")
        string(JSON rev GET "${source_json}" "rev")
        string(LENGTH "${rev}" rev_length)
        if(NOT rev_length EQUAL 40 OR NOT rev MATCHES [[^[0-9A-Fa-f]+$]])
            message(FATAL_ERROR "[cdpm] git rev must be exactly 40 hex characters.")
        endif()
        _cdpm_bs_quote_external_project_value("${url}" url_q)
        _cdpm_bs_quote_argument("${rev}" rev_q)
        set(lines "    GIT_REPOSITORY ${url_q}\n    GIT_TAG ${rev_q}")
    elseif(src_type STREQUAL "url")
        string(JSON url GET "${source_json}" "url")
        string(JSON sha GET "${source_json}" "sha256")
        string(LENGTH "${sha}" sha_length)
        if(NOT sha_length EQUAL 64 OR NOT sha MATCHES [[^[0-9A-Fa-f]+$]])
            message(FATAL_ERROR "[cdpm] URL sha256 must be exactly 64 hex characters.")
        endif()
        _cdpm_bs_quote_external_project_value("${url}" url_q)
        set(lines "    URL ${url_q}\n    URL_HASH SHA256=${sha}")
    elseif(src_type STREQUAL "local")
        string(JSON path GET "${source_json}" "path")
        _cdpm_bs_quote_external_project_value("${path}" path_q)
        set(lines "    SOURCE_DIR ${path_q}\n    DOWNLOAD_COMMAND \"\"")
    else()
        message(FATAL_ERROR "[cdpm] unsupported source type '${src_type}'.")
    endif()

    set(${out} "${lines}")
    return(PROPAGATE ${out})
endfunction()

# .. rst:
# ``_cdpm_bs_patch_line(<patches_json> <out_var>)``
#
# Generates an ExternalProject ``PATCH_COMMAND`` line (or an empty string if no patches are given).
# Patches are applied with ``git apply --whitespace=nowarn --no-index`` in source order.
function(_cdpm_bs_patch_line patches_json out)
    set(line "")
    string(JSON npatch ERROR_VARIABLE e_np LENGTH "${patches_json}")
    if(NOT e_np AND npatch GREATER 0)
        find_program(GIT_EXECUTABLE NAMES git)
        if(NOT GIT_EXECUTABLE)
            message(FATAL_ERROR "[cdpm] 'git' not found; required to apply patches.")
        endif()
        _cdpm_bs_quote_external_project_value("${GIT_EXECUTABLE}" git_q)
        # ``--no-index`` makes ``git apply`` operate purely on the filesystem relative to its working
        # directory (ExternalProject runs PATCH_COMMAND in <SOURCE_DIR>), exactly like ``patch``. Without
        # it, git walks up to any enclosing repository (the cdpm checkout / the consumer's own repo) and
        # resolves the patch paths against that repo's root instead of the isolated source tree, which
        # fails with "patch does not apply". ``--no-index`` keeps the apply self-contained and portable.
        set(patch_cmd "    PATCH_COMMAND")
        math(EXPR last "${npatch} - 1")
        foreach(i RANGE 0 ${last})
            string(JSON p GET "${patches_json}" ${i})
            _cdpm_bs_quote_external_project_value("${p}" p_q)
            if(i EQUAL 0)
                string(APPEND patch_cmd " ${git_q} apply --whitespace=nowarn --no-index ${p_q}")
            else()
                string(APPEND patch_cmd "\n        COMMAND ${git_q} apply --whitespace=nowarn --no-index ${p_q}")
            endif()
        endforeach()
        set(line "${patch_cmd}")
    endif()

    set(${out} "${line}")
    return(PROPAGATE ${out})
endfunction()

# .. rst:
# ``_cdpm_bs_miniproject_header(<project_name> <out_var>)``
#
# Generates the common header for an ExternalProject-based mini-project.
function(_cdpm_bs_miniproject_header project_name out)
    set(header "cmake_minimum_required(VERSION 3.25)\n")
    string(APPEND header "project(${project_name} NONE)\n")
    string(APPEND header "include(ExternalProject)\n")
    set(${out} "${header}")
    return(PROPAGATE ${out})
endfunction()
