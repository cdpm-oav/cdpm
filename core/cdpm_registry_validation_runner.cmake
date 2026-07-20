cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED CDPM_REGISTRY_VALIDATION_PATH OR CDPM_REGISTRY_VALIDATION_PATH STREQUAL "")
    message(FATAL_ERROR "[cdpm] registry validation runner requires CDPM_REGISTRY_VALIDATION_PATH.")
endif()

include(cdpm_config)
_cdpm_registry_validate_repo_fatal("${CDPM_REGISTRY_VALIDATION_PATH}")
