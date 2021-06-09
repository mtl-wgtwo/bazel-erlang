load(":erlang_home.bzl", "ErlangHomeProvider", "ErlangVersionProvider")
load(
    ":bazel_erlang_defs.bzl",
    "BEGINS_WITH_FUN",
    "ErlangLibInfo",
    "ErlangPrecompileInfo",
    "QUERY_ERL_VERSION",
    "output_file",
    "unique_dirnames",
)

def _create_script(dest_dir, erlang_version, path, headers):
    script = """
          set -euo pipefail

          mkdir -p {dest_dir} {dest_dir}/../include {dest_dir}/../priv/asn1db
          export HOME=$PWD

          for f in {headers}
          do
            touch {dest_dir}/../include/$f
          done

          {begins_with_fun}
          V=$({erlang_home}/bin/{query_erlang_version})
          if ! beginswith "{erlang_version}" "$V"; then
              echo "Erlang version mismatch (Expected {erlang_version}, found $V)"
              exit 1
          fi

          {erlang_home}/bin/erlc $@
          mv {dest_dir}/*.hrl {dest_dir}/../include
          mv {dest_dir}/*.asn1db {dest_dir}/../priv/asn1db
      """.format(
        dest_dir = dest_dir,
        begins_with_fun = BEGINS_WITH_FUN,
        query_erlang_version = QUERY_ERL_VERSION,
        erlang_version = erlang_version,
        erlang_home = path,
        headers = headers,
    )
    return script

def _asn1_impl(ctx):
    erlang_version = ctx.attr._erlang_version[ErlangVersionProvider].version

    dest_prefix = ""
    if ctx.attr.dest == "test":
        dest_prefix = "test/"

    # and output file "asn1/foo.asn1" will generate
    #
    erl_files = [output_file(ctx, src, dest_prefix + "src", ".asn1", ".erl") for src in ctx.files.srcs]
    hrl_files = [output_file(ctx, src, dest_prefix + "include", ".asn1", ".hrl") for src in ctx.files.srcs]
    asn1db_files = [output_file(ctx, src, dest_prefix + "priv/asn1db", ".asn1", ".asn1db") for src in ctx.files.srcs]
    hrl_file_set = ""
    for file in hrl_files:
        hrl_file_set = hrl_file_set + " " + file.basename  #file.short_path

    #hrl_file_set = [file.short_path for file in hrl_files]

    if len(erl_files) > 0:
        dest_dir = erl_files[0].dirname

        erl_args = ctx.actions.args()
        erl_args.add("+noobj")

        for dir in unique_dirnames(ctx.files.hdrs):
            erl_args.add("-I", dir)

        erl_args.add("-o", dest_dir)

        erl_args.add_all(ctx.attr.erlc_opts)

        erl_args.add_all(ctx.files.srcs)

        script = _create_script(dest_dir, erlang_version, ctx.attr._erlang_home[ErlangHomeProvider].path, hrl_file_set)
        inputs = []
        inputs.extend(ctx.files.hdrs)
        inputs.extend(ctx.files.srcs)
        for dep in ctx.attr.deps:
            lib_info = dep[ErlangLibInfo]
            inputs.extend(lib_info.include)
            inputs.extend(lib_info.beam)

        inputs.extend(ctx.files.beam)

        ctx.actions.run_shell(
            inputs = inputs,
            outputs = erl_files + hrl_files + asn1db_files,
            command = script,
            arguments = [erl_args],
            mnemonic = "ASN1",
        )

    return [
        DefaultInfo(files = depset(erl_files + hrl_files)),
        ErlangPrecompileInfo(
            include = hrl_files,
            source = erl_files,
        ),
    ]

asn1 = rule(
    implementation = _asn1_impl,
    attrs = {
        "_erlang_home": attr.label(default = ":erlang_home"),
        "_erlang_version": attr.label(default = ":erlang_version"),
        "hdrs": attr.label_list(allow_files = [".hrl"]),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = [".asn1"],
        ),
        "beam": attr.label_list(allow_files = [".beam"]),
        "deps": attr.label_list(providers = [ErlangLibInfo]),
        "erlc_opts": attr.string_list(),
        "dest": attr.string(
            default = "ebin",
        ),
    },
)
