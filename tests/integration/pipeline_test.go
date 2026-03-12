//go:build integration

// Integration tests require Windows and a running named pipe server.
// Run with: go test -tags integration ./tests/integration/
//
// These tests spin up a real daemon goroutine using the production named pipe
// and verify end-to-end message delivery using RecordingNotifier.
package integration

import (
	"testing"
)

// TODO: integration tests require Windows named pipe support.
// Implement after the binary is deployed to a Windows test runner.
// See plan: tests/integration/pipeline_test.go

func TestIntegrationPlaceholder(t *testing.T) {
	t.Skip("integration tests require Windows -- run with -tags integration on windows-latest CI")
}
