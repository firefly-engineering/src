go_binary(
    name = "go-hello-world",
    srcs = ["main.go"],
    deps = [
        "godeps//vendor/golang.org/x/example/hello/reverse:reverse",
    ],
    visibility = ["PUBLIC"],
)
