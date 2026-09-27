include(cdpm_config)
set(meta [[{"default_version":"12.1.0","versions":{"12.1.0":{"compat_version":"12.0.0"},"12.2.0":{"compat_version":"12.0.0"}}}]])
set_property(GLOBAL PROPERTY CDPM_EFFECTIVE_CONFIG [[{"packages":{"demo":{"version":"12.2.0"}}}]])
cdpm_resolve_version(demo "${meta}" "12.1.0" version compat EXACT)
