load("@prelude//:rules.bzl", "go_library", "go_test")

go_library(
    name = "greeting",
    package_name = "github.com/firefly-engineering/src/experimental/go-hello-world/greeting",
    srcs = ["greeting.go"],
    visibility = ["PUBLIC"],
)

go_test(
    name = "greeting_test",
    srcs = ["greeting_test.go"],
    target_under_test = ":greeting",
)
