# Copyright 2021 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Rule for creating Debian packages."""

load("//pkg:providers.bzl", "PackageArtifactInfo", "PackageVariablesInfo")
load("//pkg/private:util.bzl", "setup_output_files")

_tar_filetype = [".tar", ".tar.gz", ".tgz", ".tar.bz2", "tar.xz"]

def _pkg_deb_impl(ctx):
    """The implementation for the pkg_deb rule."""

    package_file_name = ctx.attr.package_file_name
    if not package_file_name:
        package_file_name = "%s_%s_%s.deb" % (
            ctx.attr.package,
            ctx.attr.version,
            ctx.attr.architecture,
        )

    outputs, output_file, output_name = setup_output_files(
        ctx,
        package_file_name = package_file_name,
    )

    changes_file = ctx.actions.declare_file(output_name.rsplit(".", 1)[0] + ".changes")
    outputs.append(changes_file)

    files = [ctx.file.data]
    args = [
        "--output=" + output_file.path,
        "--changes=" + changes_file.path,
        "--data=" + ctx.file.data.path,
        "--package=" + ctx.attr.package,
        "--maintainer=" + ctx.attr.maintainer,
    ]

    # Version and description can be specified by a file or inlined
    if ctx.attr.architecture_file:
        if ctx.attr.architecture != "all":
            fail("Both architecture and architecture_file attributes were specified")
        args += ["--architecture=@" + ctx.file.architecture_file.path]
        files += [ctx.file.architecture_file]
    else:
        args += ["--architecture=" + ctx.attr.architecture]

    if ctx.attr.preinst:
        args += ["--preinst=@" + ctx.file.preinst.path]
        files += [ctx.file.preinst]
    if ctx.attr.postinst:
        args += ["--postinst=@" + ctx.file.postinst.path]
        files += [ctx.file.postinst]
    if ctx.attr.prerm:
        args += ["--prerm=@" + ctx.file.prerm.path]
        files += [ctx.file.prerm]
    if ctx.attr.postrm:
        args += ["--postrm=@" + ctx.file.postrm.path]
        files += [ctx.file.postrm]
    if ctx.attr.config:
        args += ["--config=@" + ctx.file.config.path]
        files += [ctx.file.config]
    if ctx.attr.templates:
        args += ["--templates=@" + ctx.file.templates.path]
        files += [ctx.file.templates]
    if ctx.attr.triggers:
        args += ["--triggers=@" + ctx.file.triggers.path]
        files += [ctx.file.triggers]

    # Conffiles can be specified by a file or a string list
    if ctx.attr.conffiles_file:
        if ctx.attr.conffiles:
            fail("Both conffiles and conffiles_file attributes were specified")
        args += ["--conffile=@" + ctx.file.conffiles_file.path]
        files += [ctx.file.conffiles_file]
    elif ctx.attr.conffiles:
        args += ["--conffile=%s" % cf for cf in ctx.attr.conffiles]

    # Version and description can be specified by a file or inlined
    if ctx.attr.version_file:
        if ctx.attr.version:
            fail("Both version and version_file attributes were specified")
        args += ["--version=@" + ctx.file.version_file.path]
        files += [ctx.file.version_file]
    elif ctx.attr.version:
        args += ["--version=" + ctx.attr.version]
    else:
        fail("Neither version_file nor version attribute was specified")

    if ctx.attr.description_file:
        if ctx.attr.description:
            fail("Both description and description_file attributes were specified")
        args += ["--description=@" + ctx.file.description_file.path]
        files += [ctx.file.description_file]
    elif ctx.attr.description:
        args += ["--description=" + ctx.attr.description]
    else:
        fail("Neither description_file nor description attribute was specified")

    # Built using can also be specified by a file or inlined (but is not mandatory)
    if ctx.attr.built_using_file:
        if ctx.attr.built_using:
            fail("Both build_using and built_using_file attributes were specified")
        args += ["--built_using=@" + ctx.file.built_using_file.path]
        files += [ctx.file.built_using_file]
    elif ctx.attr.built_using:
        args += ["--built_using=" + ctx.attr.built_using]

    if ctx.attr.depends_file:
        if ctx.attr.depends:
            fail("Both depends and depends_file attributes were specified")
        args += ["--depends=@" + ctx.file.depends_file.path]
        files += [ctx.file.depends_file]
    elif ctx.attr.depends:
        args += ["--depends=" + d for d in ctx.attr.depends]

    if ctx.attr.priority:
        args += ["--priority=" + ctx.attr.priority]
    if ctx.attr.section:
        args += ["--section=" + ctx.attr.section]
    if ctx.attr.homepage:
        args += ["--homepage=" + ctx.attr.homepage]

    args += ["--distribution=" + ctx.attr.distribution]
    args += ["--urgency=" + ctx.attr.urgency]
    args += ["--suggests=" + d for d in ctx.attr.suggests]
    args += ["--enhances=" + d for d in ctx.attr.enhances]
    args += ["--conflicts=" + d for d in ctx.attr.conflicts]
    args += ["--breaks=" + d for d in ctx.attr.breaks]
    args += ["--pre_depends=" + d for d in ctx.attr.predepends]
    args += ["--recommends=" + d for d in ctx.attr.recommends]
    args += ["--replaces=" + d for d in ctx.attr.replaces]
    args += ["--provides=" + d for d in ctx.attr.provides]

    ctx.actions.run(
        mnemonic = "MakeDeb",
        executable = ctx.executable._make_deb,
        arguments = args,
        inputs = files,
        outputs = [output_file, changes_file],
        env = {
            "LANG": "en_US.UTF-8",
            "LC_CTYPE": "UTF-8",
            "PYTHONIOENCODING": "UTF-8",
            "PYTHONUTF8": "1",
        },
    )
    output_groups = {
        "out": [ctx.outputs.out],
        "deb": [output_file],
        "changes": [changes_file],
    }
    return [
        OutputGroupInfo(**output_groups),
        DefaultInfo(
            files = depset([output_file]),
            runfiles = ctx.runfiles(files = outputs),
        ),
        PackageArtifactInfo(
            label = ctx.label.name,
            file = output_file,
            file_name = output_name,
        ),
    ]

# A rule for creating a deb file, see README.md
pkg_deb_impl = rule(
    implementation = _pkg_deb_impl,
    attrs = {
        # @unsorted-dict-items
        "data": attr.label(
            doc = """A tar file that contains the data for the debian package.""",
            mandatory = True,
            allow_single_file = _tar_filetype,
        ),
        "package": attr.string(
            doc = "The name of the package",
            mandatory = True,
        ),
        "architecture": attr.string(
            default = "all",
            doc = """Package architecture. Must not be used with architecture_file.""",
        ),
        "architecture_file": attr.label(
            doc = """File that contains the package architecture.
            Must not be used with architecture.""",
            allow_single_file = True,
        ),
        "maintainer": attr.string(
            doc = "The maintainer of the package.",
            mandatory = True,
        ),
        "version": attr.string(
            doc = """Package version. Must not be used with `version_file`.""",
        ),
        "version_file": attr.label(
            doc = """File that contains the package version.
            Must not be used with `version`.""",
            allow_single_file = True,
        ),
        "config": attr.label(
            doc = """config file used for debconf integration.
            See https://www.debian.org/doc/debian-policy/ch-binary.html#prompting-in-maintainer-scripts.""",
            allow_single_file = True,
        ),
        "description": attr.string(
            doc = """The package description. Must not be used with `description_file`.""",
        ),
        "description_file": attr.label(
            doc = """The package description. Must not be used with `description`.""",
            allow_single_file = True
        ),
        "distribution": attr.string(
            doc = """"distribution: See http://www.debian.org/doc/debian-policy.""",
            default = "unstable",
        ),
        "urgency": attr.string(
            doc = """"urgency: See http://www.debian.org/doc/debian-policy.""",
            default = "medium",
        ),
        "preinst": attr.label(
            doc = """"The pre-install script for the package.
            See http://www.debian.org/doc/debian-policy/ch-maintainerscripts.html.""",
            allow_single_file = True,
        ),
        "postinst": attr.label(
            doc = """The post-install script for the package.
            See http://www.debian.org/doc/debian-policy/ch-maintainerscripts.html.""",
            allow_single_file = True,
        ),
        "prerm": attr.label(
            doc = """The pre-remove script for the package.
            See http://www.debian.org/doc/debian-policy/ch-maintainerscripts.html.""",
            allow_single_file = True,
        ),
        "postrm": attr.label(
            doc = """The post-remove script for the package.
            See http://www.debian.org/doc/debian-policy/ch-maintainerscripts.html.""",
            allow_single_file = True,
        ),
        "templates": attr.label(
            doc = """templates file used for debconf integration.
            See https://www.debian.org/doc/debian-policy/ch-binary.html#prompting-in-maintainer-scripts.""",
            allow_single_file = True,
        ),
        "triggers": attr.label(
            doc = """triggers file for configuring installation events exchanged by packages.
            See https://wiki.debian.org/DpkgTriggers.""",
            allow_single_file = True,
        ),
        "built_using": attr.string(
            doc="""The tool that were used to build this package provided either inline (with built_using) or from a file (with built_using_file)."""
        ),
        "built_using_file": attr.label(
            doc="""The tool that were used to build this package provided either inline (with built_using) or from a file (with built_using_file).""",
            allow_single_file = True
        ),
        "conffiles": attr.string_list(
            doc = """The list of conffiles or a file containing one conffile per line. Each item is an absolute path on the target system where the deb is installed.
See https://www.debian.org/doc/debian-policy/ch-files.html#s-config-files.""",
            default = [],
        ),
        "conffiles_file": attr.label(
            doc = """The list of conffiles or a file containing one conffile per line. Each item is an absolute path on the target system where the deb is installed.
See https://www.debian.org/doc/debian-policy/ch-files.html#s-config-files.""",
            allow_single_file = True,
        ),
        "priority": attr.string(
            doc = """The priority of the package.
            See http://www.debian.org/doc/debian-policy/ch-archive.html#s-priorities.""",
        ),
        "section": attr.string(
            doc = """The section of the package.
            See http://www.debian.org/doc/debian-policy/ch-archive.html#s-subsections.""",
        ),
        "homepage": attr.string(doc = """The homepage of the project."""),

        "breaks": attr.string_list(
            doc = """See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            default = [],
        ),
        "conflicts": attr.string_list(
            doc = """See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            default = [],
        ),
        "depends": attr.string_list(
            doc = """See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            default = [],
        ),
        "depends_file": attr.label(
            doc = """File that contains a list of package dependencies. Must not be used with `depends`.
            See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            allow_single_file = True,
        ),
        "enhances": attr.string_list(
            doc = """See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            default = [],
        ),
        "provides": attr.string_list(
            doc = """See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            default = [],
        ),
        "predepends": attr.string_list(
            doc = """See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            default = [],
        ),
        "recommends": attr.string_list(
            doc = """See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            default = [],
        ),
        "replaces": attr.string_list(
            doc = """See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            default = [],
        ),
        "suggests": attr.string_list(
            doc = """See http://www.debian.org/doc/debian-policy/ch-relationships.html#s-binarydeps.""",
            default = [],
        ),

        # Common attributes
        "out": attr.output(
            doc = """See Common Attributes""",
            mandatory = True
        ),
        "package_file_name": attr.string(
            doc = """See Common Attributes.
            Default: "{package}-{version}-{architecture}.deb""",
        ),
        "package_variables": attr.label(
            doc = """See Common Attributes""",
            providers = [PackageVariablesInfo],
        ),

        # Implicit dependencies.
        "_make_deb": attr.label(
            default = Label("//pkg/private/deb:make_deb"),
            cfg = "exec",
            executable = True,
            allow_files = True,
        ),
    },
    provides = [PackageArtifactInfo],
)

def pkg_deb(name, archive_name = None, **kwargs):
    """@wraps(pkg_deb_impl)."""
    if archive_name:
        # buildifier: disable=print
        print("'archive_name' is deprecated. Use 'package_file_name' or 'out' to name the output.")
        if kwargs.get("package_file_name"):
            fail("You may not set both 'archive_name' and 'package_file_name'.")
    pkg_deb_impl(
        name = name,
        out = (archive_name or name) + ".deb",
        **kwargs
    )
