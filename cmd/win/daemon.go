package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/kochbeck/cascade-notifier/internal/config"
	"github.com/kochbeck/cascade-notifier/internal/patterns"
	"github.com/kochbeck/cascade-notifier/internal/protocol"
)

const (
	pipeName    = `\\.\pipe\cascade-notifier`
	idleTimeout = 30 * time.Minute
)

// Notifier is the interface for delivering notifications.
// On Windows the real implementation plays sound and shows a toast.
// In tests a RecordingNotifier is injected.
type Notifier interface {
	Send(eventType, soundPath, title, body string) error
}

// Dispatcher holds daemon state.
type Dispatcher struct {
	notifier    Notifier
	configPath  string
	soundsDir   string
	logPath     string
	debounce    map[string]time.Time
	mu          sync.Mutex
}

// NewDispatcher constructs a Dispatcher with injected notifier (for testing).
func NewDispatcher(configPath, soundsDir, logPath string, n Notifier) *Dispatcher {
	return &Dispatcher{
		notifier:   n,
		configPath: configPath,
		soundsDir:  soundsDir,
		logPath:    logPath,
		debounce:   make(map[string]time.Time),
	}
}

// Dispatch processes one decoded pipe message.
func (d *Dispatcher) Dispatch(msg protocol.Message) {
	// Magic string: cascade-notifier:test:<event-type>
	// Fires named notification immediately, bypassing all pattern matching
	// and debounce. Used for production pipeline verification.
	if strings.Contains(msg.Payload, "cascade-notifier:test:") {
		d.handleMagicString(msg.Payload)
		return
	}

	cfg := config.Load(d.configPath)
	if !cfg.Enabled {
		return
	}

	var eventType patterns.EventType
	switch msg.HookType {
	case "pcr":
		response := extractPCRResponse(msg.Payload)
		eventType = patterns.ClassifyPCR(response)
	case "prc":
		cmdLine := extractPRCCommandLine(msg.Payload)
		eventType = patterns.ClassifyPRC(cmdLine, cfg.GitCommands)
	default:
		return
	}

	if eventType == patterns.EventTypeNone {
		return
	}

	if !cfg.EventEnabled(eventType.String()) {
		return
	}

	d.mu.Lock()
	debounceOK := d.checkDebounce(eventType.String(), cfg.DebounceSeconds)
	d.mu.Unlock()

	if !debounceOK {
		d.writeLog(eventType.String(), "SUPPRESSED", "debounced")
		return
	}

	title, body := notificationText(eventType)
	soundPath := filepath.Join(d.soundsDir, eventType.String()+".wav")
	if err := d.notifier.Send(eventType.String(), soundPath, title, body); err != nil {
		d.writeLog(eventType.String(), "PARTIAL", fmt.Sprintf("sound only, toast failed: %v", err))
	} else {
		d.writeLog(eventType.String(), "SENT", title)
	}
}

func (d *Dispatcher) handleMagicString(payload string) {
	events := []string{
		"task-complete", "task-error", "approval-required", "terminal-input",
	}
	for _, ev := range events {
		if strings.Contains(payload, "cascade-notifier:test:"+ev) {
			if ev == "ping" {
				d.writeLog("ping", "PONG", "cascade-notifier:test:ping received")
				return
			}
			title, body := notificationTextByName(ev)
			soundPath := filepath.Join(d.soundsDir, ev+".wav")
			d.notifier.Send(ev, soundPath, title, body) //nolint:errcheck
			d.writeLog(ev, "SENT", title+" (test)")
			return
		}
	}
	if strings.Contains(payload, "cascade-notifier:test:ping") {
		d.writeLog("ping", "PONG", "cascade-notifier:test:ping received")
		return
	}
	if strings.Contains(payload, "cascade-notifier:test:all") {
		for _, ev := range events {
			title, body := notificationTextByName(ev)
			soundPath := filepath.Join(d.soundsDir, ev+".wav")
			d.notifier.Send(ev, soundPath, title, body) //nolint:errcheck
			d.writeLog(ev, "SENT", title+" (test:all)")
			time.Sleep(500 * time.Millisecond)
		}
	}
}

// checkDebounce returns true (allow) if enough time has passed since the last
// notification of this type. Must be called with d.mu held.
func (d *Dispatcher) checkDebounce(eventType string, seconds int) bool {
	last, ok := d.debounce[eventType]
	if !ok || time.Since(last) >= time.Duration(seconds)*time.Second {
		d.debounce[eventType] = time.Now()
		return true
	}
	return false
}

func (d *Dispatcher) writeLog(eventType, status, message string) {
	if d.logPath == "" {
		return
	}
	f, err := os.OpenFile(d.logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	ts := time.Now().UTC().Format("2006-01-02T15:04:05Z")
	fmt.Fprintf(f, "%s [%s] %s: %s\n", ts, status, eventType, message)
}

func notificationText(et patterns.EventType) (title, body string) {
	return notificationTextByName(et.String())
}

func notificationTextByName(name string) (title, body string) {
	switch name {
	case "task-complete":
		return "Cascade: Task completed", "Cascade has finished the current task"
	case "task-error":
		return "Cascade: Error encountered", "An error occurred during task execution"
	case "approval-required":
		return "Cascade: Waiting for your approval", "Cascade needs your approval to proceed"
	case "terminal-input":
		return "Cascade: Terminal waiting for input", "A command may require interactive input"
	default:
		return "Cascade notification", name
	}
}

// extractPCRResponse pulls tool_info.response from the PCR JSON payload.
func extractPCRResponse(payload string) string {
	var v struct {
		ToolInfo struct {
			Response string `json:"response"`
		} `json:"tool_info"`
	}
	if err := json.Unmarshal([]byte(payload), &v); err != nil {
		return ""
	}
	return v.ToolInfo.Response
}

// extractPRCCommandLine pulls tool_info.command_line from the PRC JSON payload.
func extractPRCCommandLine(payload string) string {
	var v struct {
		ToolInfo struct {
			CommandLine string `json:"command_line"`
		} `json:"tool_info"`
	}
	if err := json.Unmarshal([]byte(payload), &v); err != nil {
		return ""
	}
	return v.ToolInfo.CommandLine
}

// runDaemon starts the named pipe server. It exits after idleTimeout with
// no connections.
func runDaemon() {
	notifierDir := notifierDir()
	d := NewDispatcher(
		filepath.Join(notifierDir, "config.json"),
		filepath.Join(notifierDir, "sounds"),
		filepath.Join(notifierDir, "notifications.log"),
		newWindowsNotifier(),
	)

	listener, err := listenPipe(pipeName)
	if err != nil {
		log.Fatalf("daemon: listen pipe: %v", err)
	}
	defer listener.Close()

	idleTimer := time.NewTimer(idleTimeout)
	defer idleTimer.Stop()

	connCh := make(chan net.Conn)
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			connCh <- conn
		}
	}()

	for {
		select {
		case conn := <-connCh:
			idleTimer.Reset(idleTimeout)
			handleConn(conn, d)
		case <-idleTimer.C:
			return
		}
	}
}

func handleConn(conn net.Conn, d *Dispatcher) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(5 * time.Second)) //nolint:errcheck
	msg, err := protocol.Decode(conn)
	if err != nil {
		return
	}
	d.Dispatch(msg)
}

// runTest sends a synthetic test event to the running daemon.
func runTest(eventType string) {
	payload := "cascade-notifier:test:" + eventType
	conn, err := dialPipe(pipeName, 2*time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "test: could not connect to daemon: %v\n", err)
		fmt.Fprintln(os.Stderr, "Is the daemon running? Try: cascade-notifier-win.exe --daemon")
		os.Exit(1)
	}
	defer conn.Close()
	if err := protocol.Encode(conn, "pcr", payload); err != nil {
		fmt.Fprintf(os.Stderr, "test: send: %v\n", err)
		os.Exit(1)
	}
}

// runShim reads stdin and forwards to the daemon, starting it if needed.
func runShim(hookType string) {
	maxBytes := 8192
	if hookType == "prc" {
		maxBytes = 2048
	}

	data := protocol.ReadStdin(os.Stdin, maxBytes)

	conn, err := dialPipe(pipeName, 100*time.Millisecond)
	if err != nil {
		// Daemon not running — try to start it.
		if startErr := startDaemon(); startErr != nil {
			// Can't start daemon; exit silently — hook must not crash Windsurf.
			return
		}
		time.Sleep(200 * time.Millisecond)
		conn, err = dialPipe(pipeName, 500*time.Millisecond)
		if err != nil {
			return // daemon didn't come up in time; skip silently
		}
	}
	defer conn.Close()

	protocol.Encode(conn, hookType, string(data)) //nolint:errcheck
}

// notifierDir returns the path to the notifier's data directory.
func notifierDir() string {
	// On Windows this is %USERPROFILE%\.windsurf-notifier.
	// USERPROFILE is set for all Windows processes including WSL interop.
	home := os.Getenv("USERPROFILE")
	if home == "" {
		home = os.Getenv("HOME")
	}
	return filepath.Join(home, ".windsurf-notifier")
}
