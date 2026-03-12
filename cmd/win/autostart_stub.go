//go:build !windows

package main

import "errors"

// startDaemon is a no-op on non-Windows platforms.
func startDaemon() error {
	return errors.New("daemon auto-start not supported on this platform")
}
