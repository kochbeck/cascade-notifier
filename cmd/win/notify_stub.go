//go:build !windows

package main

import "sync"

// WindowsNotifier is a stub for non-Windows builds.
type WindowsNotifier struct{}

func newWindowsNotifier() Notifier { return &WindowsNotifier{} }

func (wn *WindowsNotifier) Send(_, _, _, _ string) error { return nil }

// RecordingNotifier records Send calls for use in tests.
type RecordingNotifier struct {
	mu    sync.Mutex
	Calls []NotifyCall
}

// NotifyCall captures one invocation of Send.
type NotifyCall struct {
	EventType string
	SoundPath string
	Title     string
	Body      string
}

func (r *RecordingNotifier) Send(eventType, soundPath, title, body string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.Calls = append(r.Calls, NotifyCall{
		EventType: eventType,
		SoundPath: soundPath,
		Title:     title,
		Body:      body,
	})
	return nil
}

// Reset clears all recorded calls.
func (r *RecordingNotifier) Reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.Calls = nil
}

// CallCount returns the number of Send calls recorded.
func (r *RecordingNotifier) CallCount() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.Calls)
}
