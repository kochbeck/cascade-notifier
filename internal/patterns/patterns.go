// Package patterns classifies hook payloads into notification event types.
package patterns

import (
	"regexp"
	"strings"
)

// EventType identifies what kind of notification to send.
type EventType int

const (
	EventTypeNone      EventType = iota
	EventTypeTaskComplete         // pcr: no special pattern matched
	EventTypeTaskError            // pcr: error pattern matched
	EventTypeApproval             // pcr: approval-waiting pattern matched
	EventTypeTerminalInput        // prc: interactive command detected
)

func (e EventType) String() string {
	switch e {
	case EventTypeTaskComplete:
		return "task-complete"
	case EventTypeTaskError:
		return "task-error"
	case EventTypeApproval:
		return "approval-required"
	case EventTypeTerminalInput:
		return "terminal-input"
	default:
		return "none"
	}
}

// approval patterns: specific phrases that indicate Cascade is waiting.
// Uses substring matching (case-sensitive) to avoid false positives.
var approvalSubstrings = []string{
	"waiting for approval",
	"waiting for your approval",
	"requires approval",
	"needs your approval",
	"approve this",
	"approve the ",
	"Do you want to proceed",
	"Would you like to continue",
	"Would you like me to",
	"Should I proceed",
	"Please confirm",
	"need your permission",
	"requires your permission",
}

// error patterns: specific phrases that indicate a failure occurred.
var errorSubstrings = []string{
	"Error:",
	"error occurred",
	"error encountered",
	"build failed",
	"command failed",
	"task failed",
	"compilation failed",
	"install failed",
	"deploy failed",
	"unhandled exception",
	"threw an exception",
	"Cannot find ",
	"Could not find ",
	"Could not connect",
	"Could not resolve",
	"fatal error",
	"stack trace",
	"Traceback ",
}

// prc patterns: command-line strings that indicate interactive input is needed.
var terminalInputRegexps = []*regexp.Regexp{
	regexp.MustCompile(`\bsudo\s`),
	regexp.MustCompile(`\bssh\b`),
	regexp.MustCompile(`\bscp\b`),
	regexp.MustCompile(`\bsftp\b`),
	regexp.MustCompile(`\bssh-copy-id\b`),
	regexp.MustCompile(`\bdocker\s+login\b`),
	regexp.MustCompile(`\brunas\b`),
	regexp.MustCompile(`\bnpm\s+login\b`),
	regexp.MustCompile(`\bnpm\s+adduser\b`),
	regexp.MustCompile(`\baz\s+login\b`),
	regexp.MustCompile(`\bgcloud\s+auth\s+login\b`),
	regexp.MustCompile(`\baws\s+configure\b`),
	regexp.MustCompile(`\bkinit\b`),
	regexp.MustCompile(`\bpasswd\b`),
}

// gitRemoteRegexp matches git push/pull/fetch/clone.
var gitRemoteRegexp = regexp.MustCompile(`\bgit\s+(push|pull|fetch|clone)\b`)

// ClassifyPCR classifies a post_cascade_response payload.
// If the response is empty, EventTypeNone is returned (no notification).
// Otherwise approval is checked first (highest priority), then error, then
// task-complete as the default.
func ClassifyPCR(response string) EventType {
	if strings.TrimSpace(response) == "" {
		return EventTypeNone
	}

	// Approval check (highest priority)
	for _, s := range approvalSubstrings {
		if strings.Contains(response, s) {
			return EventTypeApproval
		}
	}

	// Error check
	for _, s := range errorSubstrings {
		if strings.Contains(response, s) {
			return EventTypeTaskError
		}
	}

	return EventTypeTaskComplete
}

// ClassifyPRC classifies a post_run_command payload.
// gitCommandsEnabled controls whether git push/pull/fetch/clone triggers a
// notification (users opt in because those operations are common).
func ClassifyPRC(commandLine string, gitCommandsEnabled bool) EventType {
	if strings.TrimSpace(commandLine) == "" {
		return EventTypeNone
	}

	if gitRemoteRegexp.MatchString(commandLine) {
		if gitCommandsEnabled {
			return EventTypeTerminalInput
		}
		return EventTypeNone
	}

	for _, re := range terminalInputRegexps {
		if re.MatchString(commandLine) {
			return EventTypeTerminalInput
		}
	}

	return EventTypeNone
}
