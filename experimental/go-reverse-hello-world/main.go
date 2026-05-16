package main

import (
	"fmt"

	"github.com/firefly-engineering/src/experimental/go-reverse-hello-world/reverser"
)

func main() {
	fmt.Println(reverser.Reverse("Hello, Firefly!"))
}
