ErlangLibInfo = provider(
    doc = "Compiled Erlang sources",
    fields = {
        'hdrs': 'Public Headers of the library',
        'beam_files': 'Compiled sources',
        'beam_path': 'the relative add path of the beam files'
    },
)

def unique_dirnames(files):
    dirs = []
    for f in files:
        if f.dirname not in dirs:
            dirs.append(f.dirname)
    return dirs

def declared_beam_file(ctx, directory, f):
    name = f.basename.replace(".erl", ".beam", 1)
    return ctx.actions.declare_file("/".join([directory, name]))

def compile_erlang_action(ctx, srcs=[], hdrs=[]):
    beam_path = "ebin" if not ctx.attr.testonly else "ebin_test"

    outs = [declared_beam_file(ctx, beam_path, f) for f in srcs]

    erl_args = ctx.actions.args()
    erl_args.add("-v")
    # Due to the sandbox, and the lack of any undeclared files, we should be able to just include every dir of every header
    # (after deduplication)
    for dir in unique_dirnames(hdrs):
        erl_args.add("-I", dir)

    # the headers of deps should work with `include_lib` calls
    dep_hdrs = depset(transitive = [dep[ErlangLibInfo].hdrs for dep in ctx.attr.deps])
    erl_args.add("-I", "external") # a cheat for now since we only include_lib for externals
    erl_args.add("-I", "deps") # another cheat based on the monorepo/erlang.mk layout

    # TODO: can this depset be replaced with just the beam_path from the ErlangLibInfo?
    dep_beam_files = depset(transitive = [dep[ErlangLibInfo].beam_files for dep in ctx.attr.deps])
    for dir in unique_dirnames(dep_beam_files.to_list()):
        erl_args.add("-pa", dir)

    erl_args.add("-o", outs[0].dirname)
    if ctx.attr.testonly:
        erl_args.add("-DTEST")

    erl_args.add_all(ctx.attr.erlc_opts)

    erl_args.add_all(srcs)

    dep_beam_files = depset(transitive = [dep[ErlangLibInfo].beam_files for dep in ctx.attr.deps])

    # ctx.actions.run(
    #     inputs = srcs + hdrs + dep_beam_files.to_list() + dep_hdrs.to_list(),
    #     outputs = outs,
    #     executable = "/Users/kuryloskip/kerl/23.1/bin/erlc",
    #     arguments = [erl_args],
    #     # progress_message = "Compiling beam files...",
    # )
    ctx.actions.run_shell(
        inputs = srcs + hdrs + dep_beam_files.to_list() + dep_hdrs.to_list(),
        outputs = outs,
        command = "set -x; tree && /Users/kuryloskip/kerl/23.1/bin/erlc $@",
        arguments = [erl_args]
    )

    return ErlangLibInfo(
        hdrs = depset(direct = hdrs, transitive = [dep_hdrs]),
        beam_files = depset(direct = outs),
        beam_path = beam_path,
    )

def _impl(ctx):
    erlang_lib_info = compile_erlang_action(ctx, srcs=ctx.files.srcs, hdrs=ctx.files.hdrs)

    return [
        DefaultInfo(files = erlang_lib_info.beam_files),
        erlang_lib_info,
    ]

# what we probably want for external libs is an 'rebar3_lib' or 'erlang_mk_lib'
# that understands the config tools. But this may do for now for the sake of
# testing
bazel_erlang_lib = rule(
    implementation = _impl,
    attrs = {
        "hdrs": attr.label_list(allow_files=[".hrl"]),
        "srcs": attr.label_list(allow_files=[".erl"]),
        "deps": attr.label_list(providers=[ErlangLibInfo]),
        "erlc_opts": attr.string_list(),
        #TODO: use a local repository in the workspace to bring in erlc
        # "_erlc": attr.label(
        #     default = "/Users/kuryloskip/kerl/23.1/bin/erlc",
        #     executable = True,
        # )
    },
)