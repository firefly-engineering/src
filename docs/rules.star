load("@prelude//mdbook:mdbook.bzl", "mdbook_book")

# Build the documentation site with mdbook
#
# Usage:
#   buck2 build //docs:docs      # Build documentation
#   buck2 run //docs:docs        # Serve with hot-reload
#
# Hot-reload behavior:
#   ✅ Content changes (.md, book.toml): Auto-reloads
#   ⚠️  BUCK changes (srcs): Requires restart (Ctrl+C → buck2 run)
mdbook_book(
    name = "docs",
    book_toml = "book.toml",
    srcs = glob(["src/**/*.md"]) + glob(["css/**/*.css"]) + glob(["js/**/*.js"]),
    visibility = ["PUBLIC"],
)