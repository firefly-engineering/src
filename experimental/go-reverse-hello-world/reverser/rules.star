load("@prelude//:rules.bzl", "go_library", "go_test")

go_library(
    name = "reverser",
    package_name = "github.com/firefly-engineering/src/experimental/go-reverse-hello-world/reverser",
    srcs = ["reverser.go"],
    deps = [
        "godeps//vendor/golang.org/x/example/hello/reverse:reverse",
    ],
    visibility = ["PUBLIC"],
)

go_test(
    name = "reverser_test",
    srcs = ["reverser_test.go"],
    target_under_test = ":reverser",
)
