package main

import (
	"fmt"

	"github.com/firefly-engineering/src/experimental/go-hello-world/greeting"
)

func main() {
	fmt.Println(greeting.Message("world"))
	fmt.Println("This is a Go binary built with Buck2 in our monorepo.")
}
