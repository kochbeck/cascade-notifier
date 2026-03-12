//go:build windows

package main

import (
	"os"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// startDaemon launches a detached daemon process using CreateProcess so the
// child survives after the shim exits. The daemon is the same binary with
// the --daemon flag. DETACHED_PROCESS|CREATE_NO_WINDOW ensures no console
// window appears.
func startDaemon() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}

	cmdLine, err := windows.UTF16PtrFromString(`"` + exe + `" --daemon`)
	if err != nil {
		return err
	}

	const (
		detachedProcess = 0x00000008
		createNoWindow  = 0x08000000
		flags           = detachedProcess | createNoWindow
	)

	var si syscall.StartupInfo
	var pi syscall.ProcessInformation
	si.Cb = uint32(unsafe.Sizeof(si))

	return syscall.CreateProcess(
		nil,
		cmdLine,
		nil,
		nil,
		false,
		flags,
		nil,
		nil,
		&si,
		&pi,
	)
}
