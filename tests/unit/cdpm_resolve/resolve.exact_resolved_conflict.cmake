include(cdpm_resolve)
set_property(GLOBAL PROPERTY CDPM_MERGED_REPO [[{"packages":{"demo":{"versions":{"12.2.0":{}}}}}]])
set_property(GLOBAL PROPERTY __CDPM_RESOLVER_STATUSES [[{"target:demo":"done"}]])
set_property(GLOBAL PROPERTY __CDPM_RESOLVER_RECORDS
    [[{"target:demo":{"version":"12.2.0","compat_version":"12.0.0"}}]])
_cdpm_resolver_resolve_node(TARGET demo "12.1.0" record EXACT)
