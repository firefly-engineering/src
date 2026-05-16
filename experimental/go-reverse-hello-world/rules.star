go_binary(
    name = "go-hello-world",
    srcs = ["main.go"],
    deps = [
        "//experimental/go-reverse-hello-world/reverser:reverser",
    ],
    visibility = ["PUBLIC"],
)
