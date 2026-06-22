# Test: compute.options_change_hash
include(cdpm_config)
include(cdpm_hash)
include("${CDPM_TEST_HELPERS}/helpers.cmake")

# With cdpm_config loaded, cdpm_get_package_options is available and folds the
# repository version options into the hash. Two versions with different options
# must yield different hashes.
set(CMAKE_SYSTEM_NAME "Linux")
set(CMAKE_SYSTEM_PROCESSOR "x86_64")
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_GENERATOR "Ninja")

set(meta_a [[{
    "source": {
        "type": "git",
        "url": "https://example/fmt.git"
    },
    "versions": {
        "1.0.0": {
            "rev": "deadbeefcafedeadbeefcafedeadbeefdeadbeef",
            "options": {
                "FMT_TEST": "OFF"
            }
        }
    }
}]])
set(meta_b [[{
    "source": {
        "type": "git",
        "url": "https://example/fmt.git"
    },
    "versions": {
        "1.0.0": {
            "rev": "deadbeefcafedeadbeefcafedeadbeefdeadbeef",
            "options": {
                "FMT_TEST": "ON"
            }
        }
    }
}]])

# cdpm_get_package_options consults the merged repo (keyed under "packages").
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG "")
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "{\"packages\":{\"fmt\":${meta_a}}}")
cdpm_compute_config_hash("fmt" "1.0.0" "${meta_a}" h_a)

set_property(GLOBAL PROPERTY CDPM_MERGED_REPO "{\"packages\":{\"fmt\":${meta_b}}}")
cdpm_compute_config_hash("fmt" "1.0.0" "${meta_b}" h_b)

assert_ne("${h_a}" "${h_b}" "different package options change the hash")

message(STATUS "PASS: package options participate in the config hash")
