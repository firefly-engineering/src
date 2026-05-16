package greeting

import "fmt"

func Message(who string) string {
	return fmt.Sprintf("Hello, %s from Firefly Engineering!", who)
}
