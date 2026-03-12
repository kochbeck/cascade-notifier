//go:build live

// Live tests require Windows with audio hardware and a real display.
// Run manually: go test -tags live ./tests/live/
//
// Each test fires an actual sound and toast notification so a human can
// verify the audio and visual output are correct.
package live

import (
	"testing"
)

// TODO: live tests require Windows audio and display hardware.
// Implement after the binary is deployed to a Windows desktop.
// See plan: tests/live/live_test.go

func TestLivePlaceholder(t *testing.T) {
	t.Skip("live tests require Windows with audio -- run manually with -tags live")
}
