// Package config loads and hot-reloads the notifier configuration from JSON.
package config

import (
	"encoding/json"
	"os"
)

// Config holds all user-configurable settings.
type Config struct {
	Enabled         bool `json:"enabled"`
	TerminalInput   bool `json:"terminal_input"`
	GitCommands     bool `json:"git_commands"`
	TaskComplete    bool `json:"task_complete"`
	TaskError       bool `json:"task_error"`
	ApprovalRequired bool `json:"approval_required"`
	SoundEnabled    bool `json:"sound_enabled"`
	ToastEnabled    bool `json:"toast_enabled"`
	DebounceSeconds int  `json:"debounce_seconds"`
}

// Defaults returns a Config with safe default values.
func Defaults() Config {
	return Config{
		Enabled:          true,
		TerminalInput:    false,
		GitCommands:      false,
		TaskComplete:     true,
		TaskError:        true,
		ApprovalRequired: true,
		SoundEnabled:     true,
		ToastEnabled:     true,
		DebounceSeconds:  5,
	}
}

// Load reads config from path, falling back to defaults for any missing or
// unparseable fields. It never returns an error — a broken config file always
// yields defaults so the hook never crashes Windsurf.
func Load(path string) Config {
	cfg := Defaults()

	data, err := os.ReadFile(path)
	if err != nil {
		return cfg
	}

	// Unmarshal into a map first so we can detect missing keys and leave
	// defaults intact for them.
	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		return cfg
	}

	if v, ok := raw["enabled"].(bool); ok {
		cfg.Enabled = v
	}
	if v, ok := raw["terminal_input"].(bool); ok {
		cfg.TerminalInput = v
	}
	if v, ok := raw["git_commands"].(bool); ok {
		cfg.GitCommands = v
	}
	if v, ok := raw["task_complete"].(bool); ok {
		cfg.TaskComplete = v
	}
	if v, ok := raw["task_error"].(bool); ok {
		cfg.TaskError = v
	}
	if v, ok := raw["approval_required"].(bool); ok {
		cfg.ApprovalRequired = v
	}
	if v, ok := raw["sound_enabled"].(bool); ok {
		cfg.SoundEnabled = v
	}
	if v, ok := raw["toast_enabled"].(bool); ok {
		cfg.ToastEnabled = v
	}
	if v, ok := raw["debounce_seconds"].(float64); ok {
		cfg.DebounceSeconds = int(v)
	}

	return cfg
}

// EventEnabled returns true if notifications for the given event type are
// permitted by the per-event toggles. It does NOT check the master switch or
// debounce — the caller handles those.
func (c Config) EventEnabled(eventType string) bool {
	switch eventType {
	case "task-complete":
		return c.TaskComplete
	case "task-error":
		return c.TaskError
	case "approval-required":
		return c.ApprovalRequired
	case "terminal-input":
		return c.TerminalInput
	default:
		return true
	}
}
