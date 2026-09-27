include(cdpm_config)
set(meta [[{"default_version":"12.0.0","versions":{"11.2.0":{"compat_version":"11.0.0"},"12.0.0":{"compat_version":"12.0.0"}}}]])
set_property(GLOBAL PROPERTY CDPM_LOCKFILE_JSON [[{"packages":{"demo":{"version":"11.2.0"}}}]])
cdpm_resolve_version(demo "${meta}" "12" version compat)
