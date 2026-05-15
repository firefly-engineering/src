load("@prelude//mdbook:mdbook.bzl", "mdbook_book")

# Test mdbook in different package to verify reusability
mdbook_book(
    name = "test-book",
    book_toml = "book.toml",
    srcs = [
        "src/SUMMARY.md",
        "src/introduction.md",
    ],
    visibility = ["PUBLIC"],
)
