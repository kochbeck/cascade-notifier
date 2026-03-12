//go:build live && windows

// Live tests for cascade-notifier -- require Windows with audio hardware and
// a real desktop. Each test fires an actual sound and toast notification so a
// human can verify the audio and visual output are correct.
//
// Prerequisites:
//   - Build: GOOS=windows GOARCH=amd64 go build -o dist/cascade-notifier-win.exe ./cmd/win
//   - Run on a Windows machine with audio and display:
//       go test -tags live -v ./tests/live/
//   - You should hear a distinct sound and see a toast notification for each test.
//
// TestMain starts a single daemon for the whole suite and copies the bundled
// sounds into a temp directory so the daemon can find them.
package live

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var (
	liveBin     string // path to cascade-notifier-win.exe
	liveEnv     []string
	liveLogPath string
)

// TestMain sets up a shared daemon for the entire live test suite.
func TestMain(m *testing.M) {
	bin, err := findBinary()
	if err != nil {
		fmt.Fprintf(os.Stderr, "SKIP: %v\n", err)
		os.Exit(0)
	}
	liveBin = bin

	tmpDir, err := os.MkdirTemp("", "cascade-live-*")
	if err != nil {
		fmt.Fprintf(os.Stderr, "MkdirTemp: %v\n", err)
		os.Exit(1)
	}
	defer os.RemoveAll(tmpDir)

	notifierDir := filepath.Join(tmpDir, ".windsurf-notifier")
	soundsDir := filepath.Join(notifierDir, "sounds")
	if err := os.MkdirAll(soundsDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "mkdir: %v\n", err)
		os.Exit(1)
	}

	// Copy bundled WAV files from the repo so the daemon plays real sounds.
	repoSounds := filepath.Join(filepath.Dir(bin), "..", "..", "sounds")
	_ = copyWavFiles(repoSounds, soundsDir) // best-effort; tests note if files are missing

	liveLogPath = filepath.Join(notifierDir, "notifications.log")

	// Write config with sound and toast enabled.
	cfgPath := filepath.Join(notifierDir, "config.json")
	if err := os.WriteFile(cfgPath, []byte(`{
  "enabled": true,
  "terminal_input": true,
  "git_commands": false,
  "task_complete": true,
  "task_error": true,
  "approval_required": true,
  "sound_enabled": true,
  "toast_enabled": true,
  "debounce_seconds": 0
}`), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write config: %v\n", err)
		os.Exit(1)
	}

	// Build env with USERPROFILE pointing to temp dir.
	liveEnv = make([]string, 0, len(os.Environ())+1)
	for _, e := range os.Environ() {
		if !strings.HasPrefix(strings.ToUpper(e), "USERPROFILE=") {
			liveEnv = append(liveEnv, e)
		}
	}
	liveEnv = append(liveEnv, "USERPROFILE="+tmpDir)

	// Kill any pre-existing daemon.
	exec.Command("taskkill", "/F", "/IM", "cascade-notifier-win.exe").Run() //nolint:errcheck
	time.Sleep(300 * time.Millisecond)

	// Start daemon.
	daemon := exec.Command(bin, "--daemon")
	daemon.Env = liveEnv
	if err := daemon.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "start daemon: %v\n", err)
		os.Exit(1)
	}
	time.Sleep(400 * time.Millisecond)

	code := m.Run()

	daemon.Process.Kill() //nolint:errcheck
	daemon.Wait()         //nolint:errcheck
	os.Exit(code)
}

// ----------------------------------------------------------------------------
// Live tests -- observe sound + toast for each
// ----------------------------------------------------------------------------

// TestLive_TaskComplete fires the task-complete notification.
// Expected: hear task-complete.wav, see toast "Cascade: Task completed".
func TestLive_TaskComplete(t *testing.T) {
	fireAndVerify(t, "task-complete", "Cascade: Task completed")
}

// TestLive_TaskError fires the task-error notification.
// Expected: hear task-error.wav, see toast "Cascade: Error encountered".
func TestLive_TaskError(t *testing.T) {
	fireAndVerify(t, "task-error", "Cascade: Error encountered")
}

// TestLive_ApprovalRequired fires the approval-required notification.
// Expected: hear approval-required.wav, see toast "Cascade: Waiting for your approval".
func TestLive_ApprovalRequired(t *testing.T) {
	fireAndVerify(t, "approval-required", "Cascade: Waiting for your approval")
}

// TestLive_TerminalInput fires the terminal-input notification.
// Expected: hear terminal-input.wav, see toast "Cascade: Terminal waiting for input".
func TestLive_TerminalInput(t *testing.T) {
	fireAndVerify(t, "terminal-input", "Cascade: Terminal waiting for input")
}

// TestLive_SoundFallback verifies that a missing WAV file falls back to a
// Windows system sound (Asterisk or similar) rather than silence.
// Expected: hear a Windows system sound, see a toast notification.
func TestLive_SoundFallback(t *testing.T) {
	soundsDir := resolvedSoundsDir()
	wavPath := filepath.Join(soundsDir, "task-complete.wav")
	orig, err := os.ReadFile(wavPath)
	if err == nil {
		os.Remove(wavPath) //nolint:errcheck
		t.Cleanup(func() {
			os.WriteFile(wavPath, orig, 0o644) //nolint:errcheck
		})
	} else {
		t.Logf("task-complete.wav not present; fallback already active")
	}

	t.Log("Firing task-complete with missing WAV -- expect a Windows system sound")
	fireAndVerify(t, "task-complete", "Cascade: Task completed")
}

// TestLive_All fires all four notification types in sequence with 500ms gaps.
// Expected: hear four distinct sounds, see four toast notifications.
func TestLive_All(t *testing.T) {
	t.Log("Firing all four notification types -- listen for four distinct sounds")

	if err := exec.Command(liveBin, "--test", "all").Run(); err != nil {
		t.Fatalf("--test all: %v", err)
	}

	// --test all fires events 500ms apart; wait long enough for all four.
	events := []string{"task-complete", "task-error", "approval-required", "terminal-input"}
	for _, ev := range events {
		if !waitForLog(liveLogPath, "[SENT] "+ev, 6*time.Second) {
			t.Errorf("expected [SENT] %s in log", ev)
		}
	}
	if t.Failed() {
		t.Logf("log:\n%s", readLog(liveLogPath))
	}
}

// TestLive_PCRShimFullChain verifies the full hook->shim->pipe->daemon chain
// using real stdin input, not the --test shortcut.
// Expected: hear task-complete.wav, see toast.
func TestLive_PCRShimFullChain(t *testing.T) {
	t.Log("Delivering task-complete via full pcr shim chain")
	payload := fmt.Sprintf(`{"tool_info":{"response":%q}}`, "The implementation is complete.")
	cmd := exec.Command(liveBin, "pcr")
	cmd.Env = liveEnv
	cmd.Stdin = strings.NewReader(payload)
	if err := cmd.Run(); err != nil {
		t.Fatalf("shim pcr: %v", err)
	}

	if !waitForLog(liveLogPath, "[SENT] task-complete", 3*time.Second) {
		t.Fatalf("expected SENT task-complete; log:\n%s", readLog(liveLogPath))
	}
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

// fireAndVerify sends a --test event and waits for the SENT log entry.
func fireAndVerify(t *testing.T, eventType, wantTitle string) {
	t.Helper()
	t.Logf("Firing %s -- expect: %q", eventType, wantTitle)

	if err := exec.Command(liveBin, "--test", eventType).Run(); err != nil {
		t.Fatalf("--test %s: %v", eventType, err)
	}

	want := "[SENT] " + eventType
	if !waitForLog(liveLogPath, want, 3*time.Second) {
		t.Fatalf("expected %q in log within 3s; log:\n%s", want, readLog(liveLogPath))
	}
	t.Logf("Log confirmed: %s sent", eventType)
}

// findBinary locates cascade-notifier-win.exe relative to the test directory.
func findBinary() (string, error) {
	candidates := []string{
		filepath.Join("..", "..", "dist", "cascade-notifier-win.exe"),
		"cascade-notifier-win.exe",
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			abs, err := filepath.Abs(c)
			if err == nil {
				return abs, nil
			}
		}
	}
	return "", fmt.Errorf("cascade-notifier-win.exe not found -- build first: " +
		"GOOS=windows GOARCH=amd64 go build -o dist/cascade-notifier-win.exe ./cmd/win")
}

// copyWavFiles copies *.wav from src to dst. Best-effort: ignores errors.
func copyWavFiles(src, dst string) error {
	entries, err := os.ReadDir(src)
	if err != nil {
		return fmt.Errorf("read sounds dir %s: %w", src, err)
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".wav") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(src, e.Name()))
		if err != nil {
			continue
		}
		_ = os.WriteFile(filepath.Join(dst, e.Name()), data, 0o644)
	}
	return nil
}

// resolvedSoundsDir returns the sounds directory path from liveEnv.
func resolvedSoundsDir() string {
	for _, e := range liveEnv {
		if strings.HasPrefix(strings.ToUpper(e), "USERPROFILE=") {
			profile := e[len("USERPROFILE="):]
			return filepath.Join(profile, ".windsurf-notifier", "sounds")
		}
	}
	return ""
}

// waitForLog polls logPath until it contains substr or the timeout elapses.
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

// readLog returns the log file contents for diagnostic messages.
func readLog(logPath string) string {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return fmt.Sprintf("(log not found: %v)", err)
	}
	return string(data)
}
