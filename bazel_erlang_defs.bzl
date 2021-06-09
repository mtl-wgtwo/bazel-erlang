ErlangLibInfo = provider(
    doc = "Compiled Erlang sources",
    fields = {
        "lib_name": "Name of the erlang lib",
        "erlang_version": "The erlang version used to produce the beam files",
        "include": "Public header files",
        "beam": "Compiled bytecode",
        "priv": "Additional files",
        "deps": "Runtime dependencies of the compiled sources",
        "additional_src": "Additional sources for further complilation",
        "additional_asn1db": "Additional asn1db files",
    },
)

ErlangPrecompileInfo = provider(
    doc = "Compiled Erlang sources",
    fields = {
        "include": "Generated headers",
        "source": "Generated sources",
    },
)

BEGINS_WITH_FUN = """beginswith() { case $2 in "$1"*) true;; *) false;; esac; }"""
QUERY_ERL_VERSION = """erl -eval '{ok, Version} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])), io:fwrite(Version), halt().' -noshell"""

DEFAULT_ERLC_OPTS = [
    "-Werror",
    "+debug_info",
    "+warn_export_vars",
    "+warn_shadow_vars",
    "+warn_obsolete_guard",
]

DEFAULT_TEST_ERLC_OPTS = [
    "+debug_info",
    "+warn_export_vars",
    "+warn_shadow_vars",
    "+warn_obsolete_guard",
    "-DTEST=1",
]

# NOTE: we should probably fetch the separator with ctx.host_configuration.host_path_separator
def path_join(*components):
    return "/".join(components)

def _contains_by_lib_name(dep, deps):
    for d in deps:
        if d[ErlangLibInfo].lib_name == dep[ErlangLibInfo].lib_name:
            # TODO: fail if name matches but they are not identical
            return True
    return False

def flat_deps(list_of_labels_providing_erlang_lib_info):
    deps = []
    for dep in list_of_labels_providing_erlang_lib_info:
        if not _contains_by_lib_name(dep, deps):
            deps.append(dep)
            for t in dep[ErlangLibInfo].deps:
                if not _contains_by_lib_name(t, deps):
                    deps.append(t)
    return deps

def unique_dirnames(files):
    dirs = []
    for f in files:
        dirname = f.path if f.is_directory else f.dirname
        if dirname not in dirs:
            dirs.append(dirname)
    return dirs

def beam_file(ctx, src, dir):
    return output_file(ctx, src, dir, ".erl", ".beam")

def output_file(ctx, src, dir, src_suffix, dst_suffix):
    name = src.basename.replace(src_suffix, dst_suffix)
    return ctx.actions.declare_file(path_join(dir, name))
