package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/kochbeck/cascade-notifier/internal/protocol"
)

func makeConfig(t *testing.T, fields map[string]any) string {
	t.Helper()
	defaults := map[string]any{
		"enabled":          true,
		"terminal_input":   false,
		"git_commands":     false,
		"task_complete":    true,
		"task_error":       true,
		"approval_required": true,
		"sound_enabled":    true,
		"toast_enabled":    true,
		"debounce_seconds": 5,
	}
	for k, v := range fields {
		defaults[k] = v
	}
	dir := t.TempDir()
	data, _ := json.Marshal(defaults)
	path := filepath.Join(dir, "config.json")
	os.WriteFile(path, data, 0o644) //nolint:errcheck
	return path
}

func newTestDispatcher(t *testing.T, configPath string) (*Dispatcher, *RecordingNotifier) {
	t.Helper()
	rec := &RecordingNotifier{}
	d := NewDispatcher(configPath, t.TempDir(), "", rec)
	return d, rec
}

func pcrMsg(response string) protocol.Message {
	payload, _ := json.Marshal(map[string]any{
		"tool_info": map[string]any{"response": response},
	})
	return protocol.Message{HookType: "pcr", Payload: string(payload)}
}

func prcMsg(cmdLine string) protocol.Message {
	payload, _ := json.Marshal(map[string]any{
		"tool_info": map[string]any{"command_line": cmdLine},
	})
	return protocol.Message{HookType: "prc", Payload: string(payload)}
}

// --- Master switch ---

func TestDispatch_MasterSwitchOff(t *testing.T) {
	cfg := makeConfig(t, map[string]any{"enabled": false})
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(pcrMsg("Task complete."))
	if rec.CallCount() != 0 {
		t.Errorf("expected 0 calls with master switch off, got %d", rec.CallCount())
	}
}

// --- Per-event toggles ---

func TestDispatch_TaskCompleteToggleOff(t *testing.T) {
	cfg := makeConfig(t, map[string]any{"task_complete": false})
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(pcrMsg("Done, the refactor is complete."))
	if rec.CallCount() != 0 {
		t.Errorf("expected 0 calls with task_complete off, got %d", rec.CallCount())
	}
}

func TestDispatch_TaskCompleteToggleOn(t *testing.T) {
	cfg := makeConfig(t, nil)
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(pcrMsg("Done, the refactor is complete."))
	if rec.CallCount() != 1 {
		t.Errorf("expected 1 call, got %d", rec.CallCount())
	}
	if rec.Calls[0].EventType != "task-complete" {
		t.Errorf("expected task-complete, got %s", rec.Calls[0].EventType)
	}
}

func TestDispatch_TaskError(t *testing.T) {
	cfg := makeConfig(t, nil)
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(pcrMsg("Error: build failed with exit code 1"))
	if rec.CallCount() != 1 {
		t.Errorf("expected 1 call, got %d", rec.CallCount())
	}
	if rec.Calls[0].EventType != "task-error" {
		t.Errorf("expected task-error, got %s", rec.Calls[0].EventType)
	}
}

func TestDispatch_ApprovalRequired(t *testing.T) {
	cfg := makeConfig(t, nil)
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(pcrMsg("Would you like me to proceed with the deployment?"))
	if rec.CallCount() != 1 {
		t.Errorf("expected 1 call, got %d", rec.CallCount())
	}
	if rec.Calls[0].EventType != "approval-required" {
		t.Errorf("expected approval-required, got %s", rec.Calls[0].EventType)
	}
}

func TestDispatch_PCREmpty(t *testing.T) {
	cfg := makeConfig(t, nil)
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(pcrMsg(""))
	if rec.CallCount() != 0 {
		t.Errorf("expected 0 calls for empty PCR, got %d", rec.CallCount())
	}
}

// --- PRC routing ---

func TestDispatch_PRCTerminalInput_Off(t *testing.T) {
	cfg := makeConfig(t, map[string]any{"terminal_input": false})
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(prcMsg("sudo apt-get update"))
	if rec.CallCount() != 0 {
		t.Errorf("expected 0 calls with terminal_input off, got %d", rec.CallCount())
	}
}

func TestDispatch_PRCTerminalInput_On(t *testing.T) {
	cfg := makeConfig(t, map[string]any{"terminal_input": true})
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(prcMsg("sudo apt-get update"))
	if rec.CallCount() != 1 {
		t.Errorf("expected 1 call, got %d", rec.CallCount())
	}
	if rec.Calls[0].EventType != "terminal-input" {
		t.Errorf("expected terminal-input, got %s", rec.Calls[0].EventType)
	}
}

func TestDispatch_PRCRoutineCommand(t *testing.T) {
	cfg := makeConfig(t, map[string]any{"terminal_input": true})
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(prcMsg("ls -la"))
	if rec.CallCount() != 0 {
		t.Errorf("expected 0 calls for routine command, got %d", rec.CallCount())
	}
}

// --- Debounce ---

func TestDispatch_Debounce(t *testing.T) {
	cfg := makeConfig(t, map[string]any{"debounce_seconds": 60})
	d, rec := newTestDispatcher(t, cfg)
	msg := pcrMsg("Done, the refactor is complete.")
	d.Dispatch(msg) // first: allowed
	d.Dispatch(msg) // second: debounced
	if rec.CallCount() != 1 {
		t.Errorf("expected 1 call (second debounced), got %d", rec.CallCount())
	}
}

func TestDispatch_DebounceExpiry(t *testing.T) {
	cfg := makeConfig(t, map[string]any{"debounce_seconds": 0})
	d, rec := newTestDispatcher(t, cfg)
	msg := pcrMsg("Done.")
	d.Dispatch(msg)
	time.Sleep(10 * time.Millisecond)
	d.Dispatch(msg)
	if rec.CallCount() != 2 {
		t.Errorf("expected 2 calls after debounce expiry, got %d", rec.CallCount())
	}
}

// --- Magic strings ---

func TestDispatch_MagicString_TaskComplete(t *testing.T) {
	cfg := makeConfig(t, nil)
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(protocol.Message{
		HookType: "pcr",
		Payload:  "cascade-notifier:test:task-complete",
	})
	if rec.CallCount() != 1 {
		t.Errorf("expected 1 call for magic string, got %d", rec.CallCount())
	}
	if rec.Calls[0].EventType != "task-complete" {
		t.Errorf("expected task-complete, got %s", rec.Calls[0].EventType)
	}
}

func TestDispatch_MagicString_Ping(t *testing.T) {
	cfg := makeConfig(t, nil)
	// Ping should NOT call the notifier.
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(protocol.Message{
		HookType: "pcr",
		Payload:  "cascade-notifier:test:ping",
	})
	if rec.CallCount() != 0 {
		t.Errorf("ping should not fire notifier, got %d calls", rec.CallCount())
	}
}

// --- Unknown hook type ---

func TestDispatch_UnknownHookType(t *testing.T) {
	cfg := makeConfig(t, nil)
	d, rec := newTestDispatcher(t, cfg)
	d.Dispatch(protocol.Message{HookType: "unknown", Payload: "whatever"})
	if rec.CallCount() != 0 {
		t.Errorf("expected 0 calls for unknown hook type, got %d", rec.CallCount())
	}
}
