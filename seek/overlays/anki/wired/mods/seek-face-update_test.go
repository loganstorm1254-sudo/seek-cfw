package mods

import "testing"

func TestSeekVersionNewer(t *testing.T) {
	cases := []struct {
		remote, current string
		want            bool
	}{
		{"3.0.1.42d", "3.0.1.40d", true},
		{"v3.0.1.42d", "3.0.1.42d", false},
		{"3.0.1.41d", "3.0.1.42d", false},
		{"3.0.2.1d", "3.0.1.99d", true},
		{"3.0.1.40e", "3.0.1.40d", true},
	}
	for _, c := range cases {
		got := seekVersionNewer(c.remote, c.current)
		if got != c.want {
			t.Fatalf("seekVersionNewer(%q,%q)=%v want %v", c.remote, c.current, got, c.want)
		}
	}
}
