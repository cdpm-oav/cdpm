include(cdpm_config)
set(meta [[{"default_version":"11.2.0","versions":{"11.2.0":{"compat_version":"11.0.0"},"12.0.0":{"compat_version":"12.0.0"}}}]])
cdpm_resolve_version(demo "${meta}" "13" version compat)
