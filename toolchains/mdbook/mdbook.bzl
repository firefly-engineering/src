# Custom mdbook rule for Buck2

def _mdbook_impl(ctx: AnalysisContext) -> list[Provider]:
    """Implementation for mdbook rule that builds documentation."""

    # Declare the output directory for the built book
    output_dir = ctx.actions.declare_output("book", dir = True)

    # Use the package directory as the source directory for mdbook
    # This assumes the BUCK file is in the same directory as book.toml
    src_dir = ctx.label.package

    # Create a script that runs mdbook and ensures the output directory exists
    script = ctx.actions.write("mdbook_build.sh", [
        "#!/bin/bash",
        "set -euo pipefail",
        'echo "Building mdbook from {} to $1"'.format(src_dir),
        "mkdir -p $1",
        "mdbook build {} --dest-dir $1".format(src_dir),
        'echo "Listing output directory contents:"',
        "ls -la $1",
        'echo "Build completed successfully"',
    ])

    # Prepare the command to run our script with the output directory as argument
    cmd = cmd_args([
        "bash",
        script,
        output_dir.as_output(),  # This ensures Buck2 knows this action produces output_dir
    ], hidden = ctx.attrs.srcs if ctx.attrs.srcs else [])

    # Create the action to run mdbook
    ctx.actions.run(
        cmd,
        category = "mdbook_build",
    )

    # Return providers
    return [
        DefaultInfo(default_output = output_dir),
        # Add RunInfo so we can use 'buck2 run' to serve the docs
        RunInfo(args = cmd_args([
            "mdbook",
            "serve",
            src_dir,
        ])),
    ]

# Define the mdbook rule
mdbook = rule(
    impl = _mdbook_impl,
    attrs = {
        "srcs": attrs.list(attrs.source(), default = [], doc = "List of source files (markdown, book.toml, etc.) that should trigger rebuilds"),
    },
    doc = "Builds an mdbook documentation site from the current package directory",
)