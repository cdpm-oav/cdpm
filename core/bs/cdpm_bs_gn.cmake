# cdpm_bs_gn.cmake - GN + Ninja build-system driver for cdpm (stub).

include_guard(GLOBAL)

# .. rst:
# ``cdpm_bs_gn_build(<ctx_json>)``
#
# Driver for GN + Ninja packages (e.g. PDFium). Not yet implemented.
#
# Planned (commands confirmed against the GN reference - no depot_tools/gclient, fully non-interactive):
#
# * a ``.gn`` dotfile with a ``buildconfig`` must exist at the source root (or be passed via ``--dotfile``);
# * configure:
#   ``gn gen <build_dir> --root=<src_dir> --args='<args>' --check --fail-on-unused-args -q``
#   where ``<args>`` are the package's native GN build args (the effective options object, the same input
#   folded into the config hash). Passing all args via ``--args`` each run fully overwrites ``args.gn`` for
#   deterministic, reproducible configuration;
# * build: ``ninja -C <build_dir> <targets>`` (note: ``-C`` is a Ninja flag, GN has no ``-C``);
# * consume outputs: GN emits no ``*Config.cmake``. Read machine-readable build info via
#   ``gn desc <build_dir> <target> --format=json`` (sources/outputs/include_dirs/defines/libs) and/or
#   ``gn gen <build_dir> --ide=json --json-file-name=project.json``; cdpm then lays out the install tree
#   and synthesizes imported targets / a ``.cps`` file itself.
#
# ``gn`` and ``ninja`` are located via ``find_program``; all steps run through ``execute_process``.
function(cdpm_bs_gn_build ctx_json)
    message(FATAL_ERROR
        "[cdpm] build-system driver 'gn' is not yet implemented. "
        "Only the 'cmake' driver is available in this version."
    )
endfunction()
