package reverser

import "testing"

func TestReverse(t *testing.T) {
	cases := map[string]string{
		"Hello, Firefly!": "!ylferiF ,olleH",
		"":                "",
		"a":               "a",
	}
	for in, want := range cases {
		if got := Reverse(in); got != want {
			t.Errorf("Reverse(%q) = %q, want %q", in, got, want)
		}
	}
}
