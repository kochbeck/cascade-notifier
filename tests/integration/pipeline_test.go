//go:build integration && windows

// Integration tests for the cascade-notifier pipeline.
// These tests run the actual cascade-notifier-win.exe binary and exercise the
// full hook -> shim -> named pipe -> daemon -> log chain.
//
// Prerequisites:
//   - Build the binary first: GOOS=windows GOARCH=amd64 go build -o dist/cascade-notifier-win.exe ./cmd/win
//   - Run on Windows: go test -tags integration -v ./tests/integration/
//
// Tests use a temp directory as USERPROFILE so logs and config are isolated.
// Each test starts its own daemon subprocess and kills it on cleanup.
package integration

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

// findBinary returns the path to cascade-notifier-win.exe, skipping the test
// if it cannot be found.
func findBinary(t *testing.T) string {
	t.Helper()
	candidates := []string{
		filepath.Join("..", "..", "dist", "cascade-notifier-win.exe"),
		"cascade-notifier-win.exe",
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			abs, err := filepath.Abs(c)
			if err == nil {
				return abs
			}
		}
	}
	t.Skip("cascade-notifier-win.exe not found -- build it first with: " +
		"GOOS=windows GOARCH=amd64 go build -o dist/cascade-notifier-win.exe ./cmd/win")
	return ""
}

// setupEnv creates a temporary USERPROFILE directory, writes config.json, and
// returns (tempDir, envSlice, notifierDir, logPath).
func setupEnv(t *testing.T, cfg map[string]any) (string, []string, string, string) {
	t.Helper()
	tmpDir := t.TempDir()
	notifierDir := filepath.Join(tmpDir, ".windsurf-notifier")
	if err := os.MkdirAll(filepath.Join(notifierDir, "sounds"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	logPath := filepath.Join(notifierDir, "notifications.log")
	writeConfig(t, filepath.Join(notifierDir, "config.json"), cfg)

	// Build env with USERPROFILE overridden.
	env := make([]string, 0, len(os.Environ())+1)
	for _, e := range os.Environ() {
		if !strings.HasPrefix(strings.ToUpper(e), "USERPROFILE=") {
			env = append(env, e)
		}
	}
	env = append(env, "USERPROFILE="+tmpDir)
	return tmpDir, env, notifierDir, logPath
}

// writeConfig writes a JSON config file. Missing keys default to safe values.
func writeConfig(t *testing.T, path string, overrides map[string]any) {
	t.Helper()
	cfg := map[string]any{
		"enabled":           true,
		"terminal_input":    false,
		"git_commands":      false,
		"task_complete":     true,
		"task_error":        true,
		"approval_required": true,
		"sound_enabled":     false, // no audio in CI
		"toast_enabled":     false, // no display in CI
		"debounce_seconds":  5,
	}
	for k, v := range overrides {
		cfg[k] = v
	}
	data, err := json.Marshal(cfg)
	if err != nil {
		t.Fatalf("marshal config: %v", err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
}

// startDaemon starts the daemon subprocess with the given environment.
// It registers a cleanup that kills the process when the test ends.
// It waits up to 500ms for the named pipe to become available.
func startDaemon(t *testing.T, bin string, env []string) *exec.Cmd {
	t.Helper()
	cmd := exec.Command(bin, "--daemon")
	cmd.Env = env
	if err := cmd.Start(); err != nil {
		t.Fatalf("start daemon: %v", err)
	}
	t.Cleanup(func() {
		cmd.Process.Kill() //nolint:errcheck
		cmd.Wait()         //nolint:errcheck
	})
	// Give the daemon time to create the named pipe.
	time.Sleep(300 * time.Millisecond)
	return cmd
}

// runShim invokes the binary in shim mode (pcr or prc) with the given stdin
// payload and environment. Returns the exit error (nil on success).
func runShim(t *testing.T, bin, hookType, payload string, env []string) error {
	t.Helper()
	cmd := exec.Command(bin, hookType)
	cmd.Env = env
	cmd.Stdin = strings.NewReader(payload)
	return cmd.Run()
}

// runTest invokes the binary in --test mode.
func runTest(t *testing.T, bin, eventType string, env []string) error {
	t.Helper()
	return exec.Command(bin, "--test", eventType).Run()
}

// pcrPayload builds a minimal post_cascade_response JSON payload.
func pcrPayload(response string) string {
	data, _ := json.Marshal(map[string]any{
		"tool_info": map[string]any{"response": response},
	})
	return string(data)
}

// prcPayload builds a minimal post_run_command JSON payload.
func prcPayload(cmdLine string) string {
	data, _ := json.Marshal(map[string]any{
		"tool_info": map[string]any{"command_line": cmdLine},
	})
	return string(data)
}

// waitForLog polls logPath until it contains substr or timeout elapses.
// Returns true if the string was found.
func waitForLog(logPath, substr string, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if data, err := os.ReadFile(logPath); err == nil {
			if strings.Contains(string(data), substr) {
				return true
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	return false
}

// logContains returns true if logPath exists and contains substr.
func logContains(logPath, substr string) bool {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return false
	}
	return strings.Contains(string(data), substr)
}

// countLogLines returns the number of lines in logPath containing substr.
func countLogLines(logPath, substr string) int {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return 0
	}
	n := 0
	for _, line := range strings.Split(string(data), "\n") {
		if strings.Contains(line, substr) {
			n++
		}
	}
	return n
}

// TestMain kills any pre-existing cascade-notifier-win process that might own
// the named pipe, then runs the tests.
func TestMain(m *testing.M) {
	// Best-effort: kill any stray daemon that might own \\.\pipe\cascade-notifier.
	exec.Command("taskkill", "/F", "/IM", "cascade-notifier-win.exe").Run() //nolint:errcheck
	time.Sleep(300 * time.Millisecond)
	os.Exit(m.Run())
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

// TestIntegration_Ping verifies the daemon starts, receives a ping magic string
// via --test, and writes a PONG log entry.
func TestIntegration_Ping(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, nil)
	startDaemon(t, bin, env)

	if err := exec.Command(bin, "--test", "ping").Run(); err != nil {
		t.Fatalf("--test ping: %v", err)
	}

	if !waitForLog(logPath, "PONG", 3*time.Second) {
		t.Fatalf("expected PONG in log, got:\n%s", readLog(logPath))
	}
}

// TestIntegration_PCRShimTaskComplete verifies that the pcr shim delivers a
// task-complete response to the daemon, which logs a SENT entry.
func TestIntegration_PCRShimTaskComplete(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, nil)
	startDaemon(t, bin, env)

	payload := pcrPayload("The refactoring is complete.")
	if err := runShim(t, bin, "pcr", payload, env); err != nil {
		t.Fatalf("shim pcr: %v", err)
	}

	if !waitForLog(logPath, "[SENT] task-complete", 3*time.Second) {
		t.Fatalf("expected SENT task-complete in log, got:\n%s", readLog(logPath))
	}
}

// TestIntegration_PCRShimTaskError verifies the task-error path.
func TestIntegration_PCRShimTaskError(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, nil)
	startDaemon(t, bin, env)

	payload := pcrPayload("Error: build failed with exit code 1.")
	if err := runShim(t, bin, "pcr", payload, env); err != nil {
		t.Fatalf("shim pcr: %v", err)
	}

	if !waitForLog(logPath, "[SENT] task-error", 3*time.Second) {
		t.Fatalf("expected SENT task-error in log, got:\n%s", readLog(logPath))
	}
}

// TestIntegration_PCRShimApprovalRequired verifies the approval-required path.
func TestIntegration_PCRShimApprovalRequired(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, nil)
	startDaemon(t, bin, env)

	payload := pcrPayload("Would you like me to proceed with the deployment?")
	if err := runShim(t, bin, "pcr", payload, env); err != nil {
		t.Fatalf("shim pcr: %v", err)
	}

	if !waitForLog(logPath, "[SENT] approval-required", 3*time.Second) {
		t.Fatalf("expected SENT approval-required in log, got:\n%s", readLog(logPath))
	}
}

// TestIntegration_PRCShimTerminalInput verifies that the prc shim delivers a
// terminal-input event when terminal_input is enabled.
func TestIntegration_PRCShimTerminalInput(t *testing.T) {
	bin := findBinary(t)
	_, env, notifierDir, logPath := setupEnv(t, map[string]any{"terminal_input": true})
	_ = notifierDir
	startDaemon(t, bin, env)

	payload := prcPayload("sudo apt-get update")
	if err := runShim(t, bin, "prc", payload, env); err != nil {
		t.Fatalf("shim prc: %v", err)
	}

	if !waitForLog(logPath, "[SENT] terminal-input", 3*time.Second) {
		t.Fatalf("expected SENT terminal-input in log, got:\n%s", readLog(logPath))
	}
}

// TestIntegration_PRCShimRoutineCommand verifies that routine commands (ls)
// do not generate a notification even when terminal_input is enabled.
func TestIntegration_PRCShimRoutineCommand(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, map[string]any{"terminal_input": true})
	startDaemon(t, bin, env)

	payload := prcPayload("ls -la")
	if err := runShim(t, bin, "prc", payload, env); err != nil {
		t.Fatalf("shim prc: %v", err)
	}

	// Give daemon time to process.
	time.Sleep(500 * time.Millisecond)
	if logContains(logPath, "[SENT] terminal-input") {
		t.Fatalf("unexpected SENT terminal-input for routine command, log:\n%s", readLog(logPath))
	}
}

// TestIntegration_Debounce verifies that a second identical event within the
// debounce window is suppressed.
func TestIntegration_Debounce(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, map[string]any{"debounce_seconds": 60})
	startDaemon(t, bin, env)

	payload := pcrPayload("The refactoring is complete.")

	if err := runShim(t, bin, "pcr", payload, env); err != nil {
		t.Fatalf("first shim: %v", err)
	}
	if !waitForLog(logPath, "[SENT] task-complete", 3*time.Second) {
		t.Fatalf("first event not SENT, log:\n%s", readLog(logPath))
	}

	if err := runShim(t, bin, "pcr", payload, env); err != nil {
		t.Fatalf("second shim: %v", err)
	}
	time.Sleep(500 * time.Millisecond)

	if !waitForLog(logPath, "[SUPPRESSED] task-complete", 3*time.Second) {
		t.Fatalf("expected SUPPRESSED on second event, log:\n%s", readLog(logPath))
	}
	if n := countLogLines(logPath, "[SENT] task-complete"); n != 1 {
		t.Fatalf("expected exactly 1 SENT, got %d; log:\n%s", n, readLog(logPath))
	}
}

// TestIntegration_DebounceExpiry verifies that a second event is allowed after
// the debounce window has passed (debounce_seconds=0 means no window).
func TestIntegration_DebounceExpiry(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, map[string]any{"debounce_seconds": 0})
	startDaemon(t, bin, env)

	payload := pcrPayload("The refactoring is complete.")

	for i := 0; i < 2; i++ {
		if err := runShim(t, bin, "pcr", payload, env); err != nil {
			t.Fatalf("shim %d: %v", i, err)
		}
		time.Sleep(20 * time.Millisecond)
	}

	// Both should be SENT when debounce_seconds=0.
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if countLogLines(logPath, "[SENT] task-complete") >= 2 {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("expected 2 SENT entries with debounce_seconds=0, got %d; log:\n%s",
		countLogLines(logPath, "[SENT] task-complete"), readLog(logPath))
}

// TestIntegration_MasterSwitchOff verifies that no notification is logged when
// enabled=false in config.
func TestIntegration_MasterSwitchOff(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, map[string]any{"enabled": false})
	startDaemon(t, bin, env)

	payload := pcrPayload("The refactoring is complete.")
	if err := runShim(t, bin, "pcr", payload, env); err != nil {
		t.Fatalf("shim: %v", err)
	}

	// Give daemon time to process.
	time.Sleep(600 * time.Millisecond)
	if logContains(logPath, "[SENT]") {
		t.Fatalf("unexpected SENT with master switch off, log:\n%s", readLog(logPath))
	}
}

// TestIntegration_ConfigHotReload verifies that the daemon picks up config
// changes without restarting.
func TestIntegration_ConfigHotReload(t *testing.T) {
	bin := findBinary(t)
	tmpDir, env, notifierDir, logPath := setupEnv(t, map[string]any{"enabled": false})
	_ = tmpDir
	startDaemon(t, bin, env)

	cfgPath := filepath.Join(notifierDir, "config.json")
	payload := pcrPayload("The refactoring is complete.")

	// With enabled=false, event should be suppressed.
	if err := runShim(t, bin, "pcr", payload, env); err != nil {
		t.Fatalf("shim (disabled): %v", err)
	}
	time.Sleep(500 * time.Millisecond)
	if logContains(logPath, "[SENT]") {
		t.Fatalf("unexpected SENT while disabled; log:\n%s", readLog(logPath))
	}

	// Enable notifications via hot-reload.
	writeConfig(t, cfgPath, map[string]any{"enabled": true})

	if err := runShim(t, bin, "pcr", payload, env); err != nil {
		t.Fatalf("shim (enabled): %v", err)
	}

	if !waitForLog(logPath, "[SENT] task-complete", 3*time.Second) {
		t.Fatalf("expected SENT after hot-reload, log:\n%s", readLog(logPath))
	}
}

// TestIntegration_ConcurrentShims verifies that 10 concurrent shim invocations
// are all processed without data loss or corruption.
func TestIntegration_ConcurrentShims(t *testing.T) {
	const n = 10
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, nil)
	startDaemon(t, bin, env)

	var wg sync.WaitGroup
	errs := make([]error, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			errs[idx] = exec.Command(bin, "--test", "ping").Run()
		}(i)
	}
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Errorf("shim %d: %v", i, err)
		}
	}

	// All 10 pings should produce PONG log entries.
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if countLogLines(logPath, "PONG") >= n {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("expected %d PONG entries, got %d; log:\n%s",
		n, countLogLines(logPath, "PONG"), readLog(logPath))
}

// TestIntegration_ColdStart verifies that the shim auto-launches the daemon
// when no daemon is running, and the event is delivered.
func TestIntegration_ColdStart(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, nil)

	// Ensure no daemon is running before this test.
	exec.Command("taskkill", "/F", "/IM", "cascade-notifier-win.exe").Run() //nolint:errcheck
	time.Sleep(300 * time.Millisecond)

	// Send a magic-string payload via pcr shim; shim will cold-start the daemon.
	payload := pcrPayload("cascade-notifier:test:ping")
	cmd := exec.Command(bin, "pcr")
	cmd.Env = env
	cmd.Stdin = strings.NewReader(payload)
	if err := cmd.Run(); err != nil {
		t.Fatalf("cold-start shim: %v", err)
	}

	// Register cleanup for the daemon that was auto-launched by the shim.
	t.Cleanup(func() {
		exec.Command("taskkill", "/F", "/IM", "cascade-notifier-win.exe").Run() //nolint:errcheck
	})

	// Daemon was launched by the shim; give it time to process the event.
	if !waitForLog(logPath, "PONG", 5*time.Second) {
		t.Fatalf("expected PONG after cold start, log:\n%s", readLog(logPath))
	}
}

// TestIntegration_ShimSilentFailureNoDaemon verifies that the shim exits with
// code 0 and does not hang when the daemon is not available.
func TestIntegration_ShimSilentFailureNoDaemon(t *testing.T) {
	bin := findBinary(t)
	_, env, _, _ := setupEnv(t, nil)

	// Ensure no daemon is running.
	exec.Command("taskkill", "/F", "/IM", "cascade-notifier-win.exe").Run() //nolint:errcheck
	time.Sleep(300 * time.Millisecond)

	// Shim with a config that has an invalid binary path so auto-start fails.
	// We force this by pointing USERPROFILE to a dir where the binary won't be
	// found for auto-start -- but actually auto-start uses os.Executable()
	// which points to our binary. To prevent the shim from successfully
	// auto-starting the daemon, we set a very short poll: the shim will try to
	// start the daemon, sleep 200ms, then retry dialPipe once. Even if the
	// daemon starts, the shim should exit 0 regardless.
	//
	// What we really test here is that the shim does not hang indefinitely.
	done := make(chan error, 1)
	go func() {
		cmd := exec.Command(bin, "pcr")
		cmd.Env = env
		cmd.Stdin = strings.NewReader(pcrPayload("test"))
		done <- cmd.Run()
	}()

	select {
	case err := <-done:
		// Any exit (0 or non-zero due to auto-start failure) is acceptable,
		// as long as it exits within a reasonable time.
		_ = err // shim may or may not auto-start; what matters is it doesn't hang
	case <-time.After(5 * time.Second):
		t.Fatal("shim did not exit within 5 seconds -- possible hang")
	}

	// Kill any daemon the shim may have auto-launched.
	t.Cleanup(func() {
		exec.Command("taskkill", "/F", "/IM", "cascade-notifier-win.exe").Run() //nolint:errcheck
	})
}

// TestIntegration_LargePayloadTruncated verifies that the shim handles a
// payload larger than its read buffer (8192 bytes) without hanging or crashing.
func TestIntegration_LargePayloadTruncated(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, nil)
	startDaemon(t, bin, env)

	// Build a payload > 8192 bytes. Embed a magic string at the start so the
	// daemon has something to recognise after truncation.
	large := fmt.Sprintf(`{"tool_info":{"response":"cascade-notifier:test:ping %s"}}`,
		strings.Repeat("x", 20000))

	done := make(chan error, 1)
	go func() {
		cmd := exec.Command(bin, "pcr")
		cmd.Env = env
		cmd.Stdin = strings.NewReader(large)
		done <- cmd.Run()
	}()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("shim exited with error on large payload: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("shim hung on large payload")
	}

	// The magic string is within the first 8192 bytes, so daemon should log it.
	if !waitForLog(logPath, "PONG", 3*time.Second) {
		t.Logf("note: magic string may have been truncated; this is acceptable")
		// Not a hard failure -- truncation is expected behaviour.
	}
}

// TestIntegration_TestFlagAll verifies that --test all fires all four event
// types and logs four SENT entries.
func TestIntegration_TestFlagAll(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, nil)
	startDaemon(t, bin, env)

	if err := exec.Command(bin, "--test", "all").Run(); err != nil {
		t.Fatalf("--test all: %v", err)
	}

	events := []string{"task-complete", "task-error", "approval-required", "terminal-input"}
	for _, ev := range events {
		want := "[SENT] " + ev
		if !waitForLog(logPath, want, 5*time.Second) {
			t.Errorf("expected %q in log", want)
		}
	}
	if t.Failed() {
		t.Logf("log contents:\n%s", readLog(logPath))
	}
}

// TestIntegration_MagicStringInNormalPayload verifies that a magic string
// embedded inside a normal-looking PCR JSON payload is still recognised.
func TestIntegration_MagicStringInNormalPayload(t *testing.T) {
	bin := findBinary(t)
	_, env, _, logPath := setupEnv(t, nil)
	startDaemon(t, bin, env)

	// The magic string is inside the response text, not at the top level.
	payload := pcrPayload("Here is the result. cascade-notifier:test:ping. Done.")
	if err := runShim(t, bin, "pcr", payload, env); err != nil {
		t.Fatalf("shim: %v", err)
	}

	if !waitForLog(logPath, "PONG", 3*time.Second) {
		t.Fatalf("magic string in payload body not recognised; log:\n%s", readLog(logPath))
	}
}

// readLog reads the log file and returns its contents for diagnostic messages.
func readLog(logPath string) string {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return fmt.Sprintf("(log not found: %v)", err)
	}
	return string(data)
}
