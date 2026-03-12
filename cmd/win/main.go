// cascade-notifier-win.exe -- Windsurf Cascade notification daemon and shim.
//
// Modes:
//
//	cascade-notifier-win.exe --daemon   Run as persistent named pipe server
//	cascade-notifier-win.exe --test <event-type>
//	                                    Send a test notification to the daemon
//	cascade-notifier-win.exe pcr        Shim: read stdin, forward to daemon
//	cascade-notifier-win.exe prc        Shim: read stdin, forward to daemon
package main

import (
	"fmt"
	"os"
)

func main() {
	args := os.Args[1:]

	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: cascade-notifier-win.exe [--daemon | --test <event> | pcr | prc]")
		os.Exit(1)
	}

	switch args[0] {
	case "--daemon":
		runDaemon()

	case "--test":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "usage: --test <event-type>")
			fmt.Fprintln(os.Stderr, "event types: task-complete task-error approval-required terminal-input ping all")
			os.Exit(1)
		}
		runTest(args[1])

	case "pcr", "prc":
		runShim(args[0])

	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", args[0])
		os.Exit(1)
	}
}
