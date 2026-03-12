package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func writeConfig(t *testing.T, dir string, v any) string {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal config: %v", err)
	}
	path := filepath.Join(dir, "config.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	return path
}

func TestLoad_Defaults(t *testing.T) {
	cfg := Load("/nonexistent/path/config.json")
	d := Defaults()
	if cfg != d {
		t.Errorf("expected defaults, got %+v", cfg)
	}
}

func TestLoad_MalformedJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")
	if err := os.WriteFile(path, []byte("{not valid json"), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg := Load(path)
	d := Defaults()
	if cfg != d {
		t.Errorf("expected defaults for malformed JSON, got %+v", cfg)
	}
}

func TestLoad_AllFields(t *testing.T) {
	dir := t.TempDir()
	path := writeConfig(t, dir, map[string]any{
		"enabled":          false,
		"terminal_input":   true,
		"git_commands":     true,
		"task_complete":    false,
		"task_error":       false,
		"approval_required": false,
		"sound_enabled":    false,
		"toast_enabled":    false,
		"debounce_seconds": 30,
	})
	cfg := Load(path)
	if cfg.Enabled {
		t.Error("expected Enabled=false")
	}
	if !cfg.TerminalInput {
		t.Error("expected TerminalInput=true")
	}
	if !cfg.GitCommands {
		t.Error("expected GitCommands=true")
	}
	if cfg.TaskComplete {
		t.Error("expected TaskComplete=false")
	}
	if cfg.TaskError {
		t.Error("expected TaskError=false")
	}
	if cfg.ApprovalRequired {
		t.Error("expected ApprovalRequired=false")
	}
	if cfg.SoundEnabled {
		t.Error("expected SoundEnabled=false")
	}
	if cfg.ToastEnabled {
		t.Error("expected ToastEnabled=false")
	}
	if cfg.DebounceSeconds != 30 {
		t.Errorf("expected DebounceSeconds=30, got %d", cfg.DebounceSeconds)
	}
}

func TestLoad_MissingKeysUseDefaults(t *testing.T) {
	dir := t.TempDir()
	// Only override one field; all others should come from defaults.
	path := writeConfig(t, dir, map[string]any{
		"debounce_seconds": 99,
	})
	cfg := Load(path)
	d := Defaults()
	if cfg.DebounceSeconds != 99 {
		t.Errorf("expected DebounceSeconds=99, got %d", cfg.DebounceSeconds)
	}
	// Everything else should equal defaults.
	d.DebounceSeconds = 99
	if cfg != d {
		t.Errorf("unexpected field difference: got %+v, want %+v", cfg, d)
	}
}

func TestLoad_HotReload(t *testing.T) {
	dir := t.TempDir()
	path := writeConfig(t, dir, map[string]any{"enabled": true})
	cfg1 := Load(path)
	if !cfg1.Enabled {
		t.Error("expected Enabled=true on first load")
	}

	// Overwrite config file.
	path = writeConfig(t, dir, map[string]any{"enabled": false})
	cfg2 := Load(path)
	if cfg2.Enabled {
		t.Error("expected Enabled=false after hot-reload")
	}
}

func TestEventEnabled(t *testing.T) {
	cases := []struct {
		cfg       Config
		eventType string
		want      bool
	}{
		{Config{TaskComplete: true}, "task-complete", true},
		{Config{TaskComplete: false}, "task-complete", false},
		{Config{TaskError: true}, "task-error", true},
		{Config{TaskError: false}, "task-error", false},
		{Config{ApprovalRequired: true}, "approval-required", true},
		{Config{ApprovalRequired: false}, "approval-required", false},
		{Config{TerminalInput: true}, "terminal-input", true},
		{Config{TerminalInput: false}, "terminal-input", false},
		{Config{}, "unknown-event", true}, // unknown events default to enabled
	}
	for _, tc := range cases {
		got := tc.cfg.EventEnabled(tc.eventType)
		if got != tc.want {
			t.Errorf("EventEnabled(%q) = %v, want %v", tc.eventType, got, tc.want)
		}
	}
}
