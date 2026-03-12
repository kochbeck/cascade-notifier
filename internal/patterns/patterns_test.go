package patterns

import "testing"

func TestClassifyPCR_Approval(t *testing.T) {
	cases := []string{
		"I am waiting for approval before continuing.",
		"This action waiting for your approval.",
		"The operation requires approval to proceed.",
		"It needs your approval.",
		"Please approve this change.",
		"Please approve the deployment.",
		"Do you want to proceed with the deletion?",
		"Would you like to continue with the migration?",
		"Would you like me to run the tests?",
		"Should I proceed with the refactor?",
		"Please confirm before I delete the file.",
		"I need your permission to push to main.",
		"This operation requires your permission.",
	}
	for _, input := range cases {
		got := ClassifyPCR(input)
		if got != EventTypeApproval {
			t.Errorf("ClassifyPCR(%q) = %v, want approval", input, got)
		}
	}
}

func TestClassifyPCR_Error(t *testing.T) {
	cases := []string{
		"Error: file not found",
		"An error occurred during execution",
		"An error encountered in module init",
		"The build failed with exit code 1",
		"The command failed",
		"The task failed to complete",
		"compilation failed: syntax error",
		"install failed: permission denied",
		"deploy failed: timeout",
		"An unhandled exception was raised",
		"The function threw an exception",
		"Cannot find module 'express'",
		"Could not find file config.json",
		"Could not connect to database",
		"Could not resolve hostname",
		"fatal error: segmentation fault",
		"stack trace:\n  at foo()",
		"Traceback (most recent call last):",
	}
	for _, input := range cases {
		got := ClassifyPCR(input)
		if got != EventTypeTaskError {
			t.Errorf("ClassifyPCR(%q) = %v, want task-error", input, got)
		}
	}
}

func TestClassifyPCR_TaskComplete(t *testing.T) {
	cases := []string{
		"I have finished implementing the feature.",
		"The refactor is complete.",
		"Done! The tests pass.",
		"Here is the updated code.",
	}
	for _, input := range cases {
		got := ClassifyPCR(input)
		if got != EventTypeTaskComplete {
			t.Errorf("ClassifyPCR(%q) = %v, want task-complete", input, got)
		}
	}
}

func TestClassifyPCR_Empty(t *testing.T) {
	for _, input := range []string{"", "   ", "\n\t"} {
		got := ClassifyPCR(input)
		if got != EventTypeNone {
			t.Errorf("ClassifyPCR(%q) = %v, want none", input, got)
		}
	}
}

func TestClassifyPCR_ApprovalBeatsError(t *testing.T) {
	// Both patterns present: approval wins.
	input := "Error: build failed. Would you like me to fix it?"
	got := ClassifyPCR(input)
	if got != EventTypeApproval {
		t.Errorf("ClassifyPCR with both patterns = %v, want approval", got)
	}
}

// False positives: casual mentions of "error" in code context should NOT
// trigger an error notification.
func TestClassifyPCR_FalsePositives(t *testing.T) {
	cases := []string{
		// Mentioning error in passing in a code explanation
		"You can handle the error using try/catch in JavaScript.",
		// Comments about errors in code snippets
		"// log the error if it happens",
		// Ordinary completion messages that happen to contain normal words
		"The function returns nil when there is no error.",
	}
	for _, input := range cases {
		got := ClassifyPCR(input)
		if got == EventTypeTaskError {
			t.Errorf("ClassifyPCR false positive: %q classified as task-error", input)
		}
	}
}

func TestClassifyPRC_TerminalInput(t *testing.T) {
	cases := []struct {
		cmd     string
		gitEnabled bool
	}{
		{"sudo apt-get update", false},
		{"ssh user@host", false},
		{"scp file.txt user@host:/tmp", false},
		{"sftp user@host", false},
		{"ssh-copy-id user@host", false},
		{"docker login registry.example.com", false},
		{"runas /user:admin cmd", false},
		{"npm login", false},
		{"npm adduser", false},
		{"az login", false},
		{"gcloud auth login", false},
		{"aws configure", false},
		{"kinit user@REALM", false},
		{"passwd", false},
		{"git push origin main", true},
		{"git pull", true},
		{"git fetch --all", true},
		{"git clone https://github.com/foo/bar", true},
	}
	for _, tc := range cases {
		got := ClassifyPRC(tc.cmd, tc.gitEnabled)
		if got != EventTypeTerminalInput {
			t.Errorf("ClassifyPRC(%q, git=%v) = %v, want terminal-input", tc.cmd, tc.gitEnabled, got)
		}
	}
}

func TestClassifyPRC_NonTriggers(t *testing.T) {
	cases := []struct {
		cmd        string
		gitEnabled bool
	}{
		{"ls -la", false},
		{"cat README.md", false},
		{"npm install", false},
		{"npm run build", false},
		{"git status", false},
		{"git log --oneline", false},
		{"git diff", false},
		// git remote ops when git_commands is disabled
		{"git push origin main", false},
		{"git pull", false},
		{"", false},
		{"   ", false},
	}
	for _, tc := range cases {
		got := ClassifyPRC(tc.cmd, tc.gitEnabled)
		if got != EventTypeNone {
			t.Errorf("ClassifyPRC(%q, git=%v) = %v, want none", tc.cmd, tc.gitEnabled, got)
		}
	}
}

func TestClassifyPRC_TruncatedInput(t *testing.T) {
	// Simulate an 8192-byte truncated command that still contains a pattern.
	prefix := make([]byte, 8000)
	for i := range prefix {
		prefix[i] = 'a'
	}
	cmd := string(prefix) + " sudo rm -rf /"
	got := ClassifyPRC(cmd, false)
	if got != EventTypeTerminalInput {
		t.Errorf("ClassifyPRC truncated = %v, want terminal-input", got)
	}
}

func TestEventTypeString(t *testing.T) {
	cases := []struct {
		e    EventType
		want string
	}{
		{EventTypeNone, "none"},
		{EventTypeTaskComplete, "task-complete"},
		{EventTypeTaskError, "task-error"},
		{EventTypeApproval, "approval-required"},
		{EventTypeTerminalInput, "terminal-input"},
	}
	for _, tc := range cases {
		if got := tc.e.String(); got != tc.want {
			t.Errorf("EventType(%d).String() = %q, want %q", tc.e, got, tc.want)
		}
	}
}
