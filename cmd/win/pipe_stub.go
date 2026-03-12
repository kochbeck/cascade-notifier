//go:build !windows

package main

import (
	"errors"
	"net"
	"time"
)

// listenPipe is a stub on non-Windows platforms.
// Named pipes are Windows-only; unit tests exercise Dispatch() directly.
func listenPipe(_ string) (net.Listener, error) {
	return nil, errors.New("named pipes not supported on this platform")
}

// dialPipe is a stub on non-Windows platforms.
func dialPipe(_ string, _ time.Duration) (net.Conn, error) {
	return nil, errors.New("named pipes not supported on this platform")
}
