//go:build windows

package main

import (
	"unsafe"

	"github.com/go-toast/toast"
	"golang.org/x/sys/windows"
)

// WindowsNotifier delivers notifications using Win32 PlaySound and WinRT toast.
type WindowsNotifier struct{}

func newWindowsNotifier() Notifier { return &WindowsNotifier{} }

// winmmDLL is the multimedia library that provides PlaySound.
var winmmDLL = windows.NewLazyDLL("winmm.dll")
var playSoundProc = winmmDLL.NewProc("PlaySoundW")

// Send plays a WAV file and shows a toast notification.
// SND_FILENAME|SND_ASYNC|SND_NODEFAULT = 0x20000|0x1|0x2000 = 0x22001
func (wn *WindowsNotifier) Send(_, soundPath, title, body string) error {
	const flags = uintptr(0x00022001)
	path, _ := windows.UTF16PtrFromString(soundPath)
	playSoundProc.Call(uintptr(unsafe.Pointer(path)), 0, flags) //nolint:errcheck

	notif := toast.Notification{
		AppID:   `{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe`,
		Title:   title,
		Message: body,
	}
	return notif.Push()
}
