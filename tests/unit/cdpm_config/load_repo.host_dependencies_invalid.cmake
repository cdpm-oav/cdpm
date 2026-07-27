include(cdpm_config)

set(repo "${CMAKE_CURRENT_LIST_DIR}/.tmp/host-invalid.json")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/.tmp")
file(WRITE "${repo}" [[{"version":1,"packages":{"bad":"host-invalid-package.json"}}]])
file(WRITE "${CMAKE_CURRENT_LIST_DIR}/.tmp/host-invalid-package.json"
    [[{"build_system":"cmake","default_version":"1","find_package_name":"bad","version_schema":"simple","source":{"type":"local","url":"."},"dependencies":{"Perl":{"version":"1"}},"host_dependencies":{"perl":{"version":"","components":["x"]}},"versions":{"1":{}}}]])
cdpm_load_repo("${repo}")
cdpm_find_in_repo(bad found meta)
cdpm_get_package_host_dependencies(bad "${meta}" "" host_deps)
