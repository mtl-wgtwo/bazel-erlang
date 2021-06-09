load(":erlang_home.bzl", "ErlangVersionProvider")
load(
    ":bazel_erlang_defs.bzl",
    "DEFAULT_ERLC_OPTS",
    "DEFAULT_TEST_ERLC_OPTS",
    "ErlangLibInfo",
    "flat_deps",
    "path_join",
)
load(
    ":bazel_erlc.bzl",
    "erlc",
)
load(
    ":bazel_asn1.bzl",
    "asn1",
)

def _module_name(f):
    return "'{}'".format(f.basename.replace(".beam", "", 1))

def _app_file_impl(ctx):
    app_file = ctx.actions.declare_file(
        path_join("ebin", "{}.app".format(ctx.attr.app_name)),
    )

    if len(ctx.files.app_src) > 1:
        fail("Multiple .app.src files ({}) are not supported".format(ctx.files.app_src))

    modules_list = "[" + ",".join([_module_name(m) for m in ctx.files.modules]) + "]"

    if len(ctx.files.app_src) == 1:
        modules_term = "{modules," + modules_list + "}"

        # TODO: handle the data structure manipulation with erlang itself
        ctx.actions.expand_template(
            template = ctx.files.app_src[0],
            output = app_file,
            substitutions = {
                "{modules,[]}": modules_term,
                "{modules, []}": modules_term,
            },
        )
    else:
        if ctx.attr.app_version == "":
            fail("app_version must be set when app_src is empty")

        app_module = ctx.attr.app_module if ctx.attr.app_module != "" else ctx.attr.app_name + "_app"

        if len([m for m in ctx.files.modules if m.basename == app_module + ".beam"]) == 1:
            template = ctx.file._app_with_mod_file_template
        else:
            template = ctx.file._app_file_template

        project_description = ctx.attr.app_description if ctx.attr.app_description != "" else ctx.attr.app_name

        registered_list = "[" + ",".join([ctx.attr.app_name + "_sup"] + ctx.attr.app_registered) + "]"

        applications = ["kernel", "stdlib"] + ctx.attr.extra_apps
        for dep in ctx.attr.deps:
            applications.append(dep[ErlangLibInfo].lib_name)
        applications_list = "[" + ",".join(applications) + "]"

        ctx.actions.expand_template(
            template = template,
            output = app_file,
            substitutions = {
                "$(PROJECT)": ctx.attr.app_name,
                "$(PROJECT_DESCRIPTION)": project_description,
                "$(PROJECT_VERSION)": ctx.attr.app_version,
                "$(PROJECT_ID_TERM)": "",
                "$(MODULES_LIST)": modules_list,
                "$(REGISTERED_LIST)": registered_list,
                "$(APPLICATIONS_LIST)": applications_list,
                "$(PROJECT_MOD)": app_module,
                "$(PROJECT_ENV)": ctx.attr.app_env,
            },
        )

    return [
        DefaultInfo(files = depset([app_file])),
    ]

app_file = rule(
    implementation = _app_file_impl,
    attrs = {
        "_erlang_home": attr.label(default = ":erlang_home"),
        "_erlang_version": attr.label(default = ":erlang_version"),
        "_app_file_template": attr.label(
            default = Label("//:app_file.template"),
            allow_single_file = True,
        ),
        "_app_with_mod_file_template": attr.label(
            default = Label("//:app_with_mod_file.template"),
            allow_single_file = True,
        ),
        "app_name": attr.string(mandatory = True),
        "app_version": attr.string(),
        "app_description": attr.string(),
        "app_module": attr.string(),
        "app_registered": attr.string_list(),
        "app_env": attr.string(default = "[]"),
        "extra_apps": attr.string_list(),
        "app_src": attr.label_list(allow_files = [".app.src"]),
        "modules": attr.label_list(allow_files = [".beam"]),
        "deps": attr.label_list(providers = [ErlangLibInfo]),
    },
)

def _impl(ctx):
    compiled_files = ctx.files.app + ctx.files.beam

    deps = flat_deps(ctx.attr.deps)

    runfiles = ctx.runfiles(compiled_files + ctx.files.priv + ctx.files.hdrs)
    for dep in ctx.attr.deps:
        runfiles = runfiles.merge(dep[DefaultInfo].default_runfiles)

    return [
        ErlangLibInfo(
            lib_name = ctx.attr.app_name,
            erlang_version = ctx.attr._erlang_version[ErlangVersionProvider].version,
            include = ctx.files.hdrs,
            beam = compiled_files,
            priv = ctx.files.priv,
            deps = deps,
        ),
        DefaultInfo(
            files = depset(compiled_files + ctx.files.hdrs),
            runfiles = runfiles,
        ),
    ]

bazel_erlang_lib = rule(
    implementation = _impl,
    attrs = {
        "_erlang_version": attr.label(default = ":erlang_version"),
        "app_name": attr.string(mandatory = True),
        "hdrs": attr.label_list(allow_files = [".hrl"]),
        "app": attr.label(allow_files = [".app"]),
        "beam": attr.label_list(allow_files = [".beam", ".appup"]),
        "priv": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [ErlangLibInfo]),
    },
)

def erlang_lib(
        app_name = "",
        app_version = "",
        app_description = "",
        app_module = "",
        app_registered = [],
        app_env = "[]",
        extra_apps = [],
        erlc_opts = DEFAULT_ERLC_OPTS,
        first_srcs = [],
        extra_priv = [],
        build_deps = [],
        deps = [],
        runtime_deps = []):
    all_beam = []

    asn1_files = native.glob(["asn1/**/*.asn1"])
    asn1_deps = []
    if len(asn1_files) > 0:
        asn1_deps = [":asn1_precompile"]
        asn1(
            name = "asn1_precompile",
            hdrs = [],
            srcs = asn1_files,
            erlc_opts = _unique(erlc_opts),
        )

    if len(first_srcs) > 0:
        all_beam = all_beam + [":first_beam_files"]
        erlc(
            name = "first_beam_files",
            hdrs = native.glob(["include/**/*.hrl", "src/**/*.hrl"]),
            srcs = native.glob(first_srcs),
            erlc_opts = _unique(erlc_opts),
            dest = "ebin",
            deps = build_deps + deps,
        )

    erlc(
        name = "beam_files",
        hdrs = native.glob(["include/**/*.hrl", "src/**/*.hrl"]),
        srcs = native.glob(["src/**/*.erl"], exclude = first_srcs),
        beam = all_beam,
        erlc_opts = _unique(erlc_opts),
        dest = "ebin",
        deps = build_deps + deps,
        precompile_deps = asn1_deps,
    )

    all_beam = all_beam + [":beam_files"]

    if len(native.glob(["ebin/{}.app".format(app_name)])) == 0:
        app_file(
            name = "app_file",
            app_name = app_name,
            app_version = app_version,
            app_description = app_description,
            app_module = app_module,
            app_registered = app_registered,
            app_env = app_env,
            extra_apps = extra_apps,
            app_src = native.glob(["src/{}.app.src".format(app_name)]),
            modules = all_beam,
            deps = deps + runtime_deps,
        )
        app = ":app_file"
    else:
        app = "ebin/{}.app".format(app_name)

    bazel_erlang_lib(
        name = "bazel_erlang_lib",
        app_name = app_name,
        hdrs = native.glob(["include/**/*.hrl"]),
        app = app,
        beam = all_beam,
        priv = native.glob(["priv/**/*"] + extra_priv),
        deps = deps + runtime_deps,
        visibility = ["//visibility:public"],
    )

def _unique(l):
    r = []
    for item in l:
        if item not in r:
            r.append(item)
    return r

def test_erlang_lib(
        app_name = "",
        app_version = "",
        app_description = "",
        app_module = "",
        app_registered = [],
        app_env = "[]",
        extra_apps = [],
        erlc_opts = DEFAULT_TEST_ERLC_OPTS,
        first_srcs = [],
        extra_priv = [],
        build_deps = [],
        deps = [],
        runtime_deps = []):
    all_beam = []

    asn1_files = native.glob(["asn1/**/*.asn1"])
    asn1_deps = []
    if len(asn1_files) > 0:
        asn1_deps = [":asn1_test_precompile"]
        asn1(
            name = "asn1_test_precompile",
            hdrs = [],
            srcs = asn1_files,
            erlc_opts = _unique(erlc_opts),
            dest = "test",
            testonly = True,
        )

    if len(first_srcs) > 0:
        all_beam = all_beam + [":first_test_beam_files"]
        erlc(
            name = "first_test_beam_files",
            hdrs = native.glob(["include/**/*.hrl", "src/**/*.hrl"]),
            srcs = native.glob(first_srcs),
            erlc_opts = _unique(erlc_opts),
            dest = "test",
            deps = build_deps + deps,
            testonly = True,
        )

    erlc(
        name = "test_beam_files",
        hdrs = native.glob(["include/**/*.hrl", "src/**/*.hrl"]),
        srcs = native.glob(["src/**/*.erl"], exclude = first_srcs),
        beam = all_beam,
        erlc_opts = _unique(erlc_opts),
        dest = "test",
        deps = build_deps + deps,
        precompile_deps = asn1_deps,
        testonly = True,
    )

    all_beam = all_beam + [":test_beam_files"]

    if len(native.glob(["ebin/{}.app".format(app_name)])) == 0:
        app = ":app_file"
    else:
        app = "ebin/{}.app".format(app_name)

    bazel_erlang_lib(
        name = "test_bazel_erlang_lib",
        app_name = app_name,
        hdrs = native.glob(["include/**/*.hrl"]),
        app = app,
        beam = all_beam,
        priv = native.glob(["priv/**/*"] + extra_priv),
        deps = deps + runtime_deps,
        visibility = ["//visibility:public"],
        testonly = True,
    )
