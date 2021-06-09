load(":erlang_home.bzl", "ErlangHomeProvider", "ErlangVersionProvider")
load(
    ":bazel_erlang_defs.bzl",
    "BEGINS_WITH_FUN",
    "ErlangLibInfo",
    "ErlangPrecompileInfo",
    "QUERY_ERL_VERSION",
    "beam_file",
    "path_join",
    "unique_dirnames",
)

def _erlc_impl(ctx):
    erlang_version = ctx.attr._erlang_version[ErlangVersionProvider].version

    beam_files = [beam_file(ctx, src, ctx.attr.dest) for src in ctx.files.srcs]
    precompile_beam_files = []
    for dep in ctx.attr.precompile_deps:
        precompile_info = dep[ErlangPrecompileInfo]
        precompile_beam_files = [beam_file(ctx, src, ctx.attr.dest) for src in precompile_info.source]

    beam_files = beam_files + precompile_beam_files

    if len(beam_files) > 0:
        dest_dir = beam_files[0].dirname

        erl_args = ctx.actions.args()
        erl_args.add("-v")

        for dir in unique_dirnames(ctx.files.hdrs):
            erl_args.add("-I", dir)
            erl_args.add("-I", path_join(dir, "../.."))

        for dep in ctx.attr.precompile_deps:
            precompile_info = dep[ErlangPrecompileInfo]
            for dir in unique_dirnames(precompile_info.include):
                erl_args.add("-I", dir)

        for dep in ctx.attr.deps:
            lib_info = dep[ErlangLibInfo]
            if lib_info.erlang_version != erlang_version:
                fail("Mismatched erlang versions", erlang_version, lib_info.erlang_version)
            for dir in unique_dirnames(lib_info.include):
                erl_args.add("-I", dir)
                erl_args.add("-I", path_join(dir, "../.."))
                erl_args.add("-I", path_join(dir, "../../.."))

            for dir in unique_dirnames(lib_info.beam):
                erl_args.add("-pa", dir)

        for dir in unique_dirnames(ctx.files.beam):
            erl_args.add("-pa", dir)

        erl_args.add("-o", dest_dir)

        erl_args.add_all(ctx.attr.erlc_opts)

        erl_args.add_all(ctx.files.srcs)

        for dep in ctx.attr.precompile_deps:
            precompile_info = dep[ErlangPrecompileInfo]
            erl_args.add_all(precompile_info.source)

        script = """
          set -euo pipefail

          mkdir -p {dest_dir}
          export HOME=$PWD

          {begins_with_fun}
          V=$({erlang_home}/bin/{query_erlang_version})
          if ! beginswith "{erlang_version}" "$V"; then
              echo "Erlang version mismatch (Expected {erlang_version}, found $V)"
              exit 1
          fi

          {erlang_home}/bin/erlc $@
      """.format(
            dest_dir = dest_dir,
            begins_with_fun = BEGINS_WITH_FUN,
            query_erlang_version = QUERY_ERL_VERSION,
            erlang_version = erlang_version,
            erlang_home = ctx.attr._erlang_home[ErlangHomeProvider].path,
        )

        headers = []
        inputs = []
        inputs.extend(ctx.files.hdrs)
        inputs.extend(ctx.files.srcs)
        headers.extend(ctx.files.hdrs)

        for dep in ctx.attr.precompile_deps:
            precompile_info = dep[ErlangPrecompileInfo]
            inputs.extend(precompile_info.include)
            inputs.extend(precompile_info.source)
            headers.extend(precompile_info.include)

        for dep in ctx.attr.deps:
            lib_info = dep[ErlangLibInfo]
            inputs.extend(lib_info.include)
            inputs.extend(lib_info.beam)
            headers.extend(lib_info.include)

        inputs.extend(ctx.files.beam)

        ctx.actions.run_shell(
            inputs = inputs,
            outputs = beam_files,
            command = script,
            arguments = [erl_args],
            mnemonic = "ERLC",
        )

    return [
        DefaultInfo(files = depset(beam_files + headers)),
    ]

erlc = rule(
    implementation = _erlc_impl,
    attrs = {
        "_erlang_home": attr.label(default = ":erlang_home"),
        "_erlang_version": attr.label(default = ":erlang_version"),
        "hdrs": attr.label_list(allow_files = [".hrl"]),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = [".erl"],
        ),
        "beam": attr.label_list(allow_files = [".beam"]),
        "deps": attr.label_list(providers = [ErlangLibInfo]),
        "precompile_deps": attr.label_list(providers = [ErlangPrecompileInfo]),
        "erlc_opts": attr.string_list(),
        "dest": attr.string(
            default = "ebin",
        ),
    },
)
