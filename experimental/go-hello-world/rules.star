go_binary(
    name = "go-hello-world",
    srcs = ["main.go"],
    deps = [
        "//experimental/go-hello-world/greeting:greeting",
    ],
    visibility = ["PUBLIC"],
)
