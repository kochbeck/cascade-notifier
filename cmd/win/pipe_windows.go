//go:build windows

package main

import (
	"net"
	"time"

	winio "github.com/Microsoft/go-winio"
)

// listenPipe creates a named pipe server listener.
func listenPipe(name string) (net.Listener, error) {
	return winio.ListenPipe(name, nil)
}

// dialPipe connects to a named pipe with a timeout.
func dialPipe(name string, timeout time.Duration) (net.Conn, error) {
	return winio.DialPipe(name, &timeout)
}
