# Custom mdbook rule for Buck2

def _mdbook_impl(ctx: AnalysisContext) -> list[Provider]:
    """Implementation for mdbook rule that builds documentation."""

    # Declare the output directory for the built book
    output_dir = ctx.actions.declare_output("book", dir = True)

    # Create a temporary source directory with only the declared source files
    temp_src_dir = ctx.actions.declare_output("_temp_src", dir = True)

    # Create the script content with package name substituted
    package_name = ctx.label.package
    script_lines = [
        "#!/bin/bash",
        "set -euo pipefail",
        'echo "Setting up hermetic mdbook build"',
        'echo "Temp source dir: $1"',
        'echo "Output dir: $2"',

        # Create temporary source directory structure
        "mkdir -p $1",
        "mkdir -p $2",

        # Copy all source files to temp directory, preserving relative structure
        'echo "Copying source files to temporary directory..."',
        'PACKAGE_PREFIX="{}"'.format(package_name),
        'for src_file in "${@:3}"; do',
        '  if [[ -f "$src_file" ]]; then',
        '    # Extract relative path by removing the package prefix',
        '    if [[ "$src_file" == "$PACKAGE_PREFIX"/* ]]; then',
        '      rel_path="${src_file#$PACKAGE_PREFIX/}"',  # Remove package prefix
        '    else',
        '      rel_path="$src_file"',  # Fallback for unexpected paths
        '    fi',
        '    target_path="$1/$rel_path"',
        '    target_dir=$(dirname "$target_path")',
        '    mkdir -p "$target_dir"',
        '    cp "$src_file" "$target_path"',
        '    echo "Copied $src_file to $target_path"',
        '  fi',
        'done',

        # Convert relative output path to absolute path
        'ABS_OUTPUT="$(cd $(dirname $2) && pwd)/$(basename $2)"',
        'echo "Absolute output path: $ABS_OUTPUT"',

        # Run mdbook build from the temporary hermetic source directory
        'echo "Running: mdbook build $1 --dest-dir $ABS_OUTPUT"',
        "mdbook build $1 --dest-dir $ABS_OUTPUT",

        'echo "Listing output directory contents:"',
        "ls -la $2",
        'echo "Build completed successfully"',
    ]

    # Create a script that sets up hermetic source directory and runs mdbook
    script = ctx.actions.write("mdbook_build.sh", script_lines)

    # Prepare the command to run our script with temp src dir, output dir, and all source files
    cmd = cmd_args([
        "bash",
        script,
        temp_src_dir.as_output(),  # $1: temp source directory
        output_dir.as_output(),    # $2: output directory
    ])

    # Add all source files as additional arguments ($3, $4, ...)
    if ctx.attrs.srcs:
        cmd.add(ctx.attrs.srcs)

    # Create the action to run mdbook
    ctx.actions.run(
        cmd,
        category = "mdbook_build",
    )

    # Create serve script content with package name substituted and hot-reload support
    serve_script_lines = [
        "#!/bin/bash",
        "set -euo pipefail",
        'echo "Setting up hermetic mdbook serve with hot-reload"',

        # Create temporary directory for serving
        'TEMP_DIR=$(mktemp -d)',
        'echo "Temp serve dir: $TEMP_DIR"',

        # Function to copy all source files to temp directory
        'copy_sources() {',
        '  echo "Copying source files to temporary directory..."',
        '  PACKAGE_NAME="{}"'.format(package_name),  # Use actual package name
        '  for src_file in "$@"; do',
        '    if [[ -f "$src_file" ]]; then',
        '      # Extract relative path by finding the package pattern and taking everything after it',
        '      if [[ "$src_file" == */"$PACKAGE_NAME"/* ]]; then',
        '        rel_path="${src_file#*/$PACKAGE_NAME/}"',  # Remove everything up to and including the package
        '      else',
        '        # Fallback: use basename for files not in expected structure',
        '        rel_path="$(basename "$src_file")"',
        '      fi',
        '      target_path="$TEMP_DIR/$rel_path"',
        '      target_dir=$(dirname "$target_path")',
        '      mkdir -p "$target_dir"',
        '      cp "$src_file" "$target_path"',
        '    fi',
        '  done',
        '}',

        # Initial copy of source files
        'copy_sources "$@"',
        'echo "Initial setup complete"',

        # Start file watching in background if available
        'if command -v fswatch >/dev/null 2>&1; then',
        '  echo "Hot-reload enabled: watching source files for changes (using fswatch)"',
        '  {',
        '    # Watch all source file directories for changes',
        '    fswatch -o "$@" | while read -r num_changes; do',
        '      echo "Detected $num_changes file change(s), updating temp directory..."',
        '      copy_sources "$@"',
        '      echo "Files updated, mdbook will auto-refresh"',
        '    done',
        '  } &',
        '  FSWATCH_PID=$!',
        'elif command -v inotifywait >/dev/null 2>&1; then',
        '  echo "Hot-reload enabled: watching source files for changes (using inotifywait)"',
        '  {',
        '    while inotifywait -e modify,create,delete,move "$@" 2>/dev/null; do',
        '      echo "Detected file change(s), updating temp directory..."',
        '      copy_sources "$@"',
        '      echo "Files updated, mdbook will auto-refresh"',
        '    done',
        '  } &',
        '  FSWATCH_PID=$!',
        'else',
        '  echo "Hot-reload disabled: file watcher not found."',
        '  echo "Available options:"',
        '  echo "  - macOS: fswatch (already in Nix shell, restart shell to enable)"',
        '  echo "  - Linux: inotify-tools (install with: apt install inotify-tools)"',
        '  echo "  - Manual: edit files and refresh browser manually"',
        'fi',
        '',
        'echo ""',
        'echo "📋 Hot-reload behavior:"',
        'echo "  ✅ Content changes: Auto-reloads (edit .md files, book.toml)"',
        'echo "  ⚠️  BUCK file changes: Requires manual restart (adding/removing srcs)"',
        'echo "  💡 To restart: Press Ctrl+C, then run buck2 run again"',

        # Cleanup function
        'cleanup() {',
        '  echo "Shutting down..."',
        '  if [[ -n "${FSWATCH_PID:-}" ]]; then',
        '    kill $FSWATCH_PID 2>/dev/null || true',
        '  fi',
        '  echo "Cleaning up temporary directory: $TEMP_DIR"',
        '  rm -rf "$TEMP_DIR"',
        '}',
        'trap cleanup EXIT INT TERM',

        # Serve from the temporary hermetic source directory
        'echo "Starting mdbook serve from $TEMP_DIR (press Ctrl+C to stop)"',
        'mdbook serve "$TEMP_DIR"',
    ]

    # Create a serve script that also uses hermetic source directory
    serve_script = ctx.actions.write("mdbook_serve.sh", serve_script_lines)

    # Return providers
    return [
        DefaultInfo(default_output = output_dir),
        # Add RunInfo so we can use 'buck2 run' to serve the docs hermatically
        RunInfo(args = cmd_args([
            "bash",
            serve_script,
        ] + (ctx.attrs.srcs if ctx.attrs.srcs else []))),
    ]

# Define the mdbook rule
mdbook = rule(
    impl = _mdbook_impl,
    attrs = {
        "srcs": attrs.list(attrs.source(), default = [], doc = "List of source files (markdown, book.toml, etc.) that should trigger rebuilds"),
    },
    doc = """Builds an mdbook documentation site from hermetic sources.

    Features:
    - Hermetic builds: Only declared srcs files are included
    - Hot-reload: buck2 run watches source files and auto-refreshes browser
    - Cross-platform: Works with fswatch (macOS) or inotify-tools (Linux)

    Hot-reload limitations:
    - Content changes (.md, book.toml): Auto-reloads ✅
    - BUCK file changes (srcs): Requires manual restart ⚠️
    """,
)