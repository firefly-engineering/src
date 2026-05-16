package greeting

import "testing"

func TestMessage(t *testing.T) {
	got := Message("world")
	want := "Hello, world from Firefly Engineering!"
	if got != want {
		t.Errorf("Message(%q) = %q, want %q", "world", got, want)
	}
}
