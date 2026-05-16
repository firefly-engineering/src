rust_binary(
    name = "rs-hello-world",
    srcs = ["main.rs"],
    edition = "2021",
)

rust_test(
    name = "rs-hello-world-test",
    srcs = ["main.rs"],
    crate_root = "main.rs",
    edition = "2021",
)
