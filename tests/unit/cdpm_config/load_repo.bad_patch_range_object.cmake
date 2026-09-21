# Test: load_repo.bad_patch_range_object (WILL_FAIL)
include(cdpm_config)
set(package_json
[[{
  "patches": [
    {
      "file": "fix.patch",
      "applies_to": {
        "from": "1..2",
        "to": "2.0"
      }
    }
  ]
}]]
)

_cdpm_validate_repo_patches(test "${package_json}")

message(STATUS "UNREACHABLE: malformed patch range object should have aborted")
