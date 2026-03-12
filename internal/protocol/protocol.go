// Package protocol implements length-prefix framing for the named pipe IPC
// between the shim and the daemon.
//
// Wire format (binary, big-endian):
//
//	[ 4 bytes: uint32 message length ][ N bytes: "HOOKTYPE\tPAYLOAD" ]
//
// This framing is binary-safe: the payload may contain arbitrary bytes
// including embedded newlines, null bytes, and multi-byte UTF-8 sequences.
package protocol

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"strings"
)

// utf8BOM is the byte order mark that some Windows tools prepend to UTF-8 output.
var utf8BOM = []byte{0xEF, 0xBB, 0xBF}

// Message is a decoded pipe message.
type Message struct {
	HookType string // "pcr" or "prc"
	Payload  string // raw JSON payload from stdin (possibly truncated)
}

// Encode writes a length-prefixed message to w.
func Encode(w io.Writer, hookType, payload string) error {
	body := hookType + "\t" + payload
	length := uint32(len(body))
	if err := binary.Write(w, binary.BigEndian, length); err != nil {
		return fmt.Errorf("write length: %w", err)
	}
	_, err := io.WriteString(w, body)
	return err
}

// Decode reads one length-prefixed message from r.
func Decode(r io.Reader) (Message, error) {
	var length uint32
	if err := binary.Read(r, binary.BigEndian, &length); err != nil {
		return Message{}, fmt.Errorf("read length: %w", err)
	}
	if length == 0 {
		return Message{}, nil
	}

	buf := make([]byte, length)
	if _, err := io.ReadFull(r, buf); err != nil {
		return Message{}, fmt.Errorf("read body: %w", err)
	}

	parts := strings.SplitN(string(buf), "\t", 2)
	if len(parts) != 2 {
		return Message{}, fmt.Errorf("malformed message: missing tab separator")
	}
	return Message{HookType: parts[0], Payload: parts[1]}, nil
}

// StripBOM removes the UTF-8 byte order mark from the start of b if present.
func StripBOM(b []byte) []byte {
	if bytes.HasPrefix(b, utf8BOM) {
		return b[len(utf8BOM):]
	}
	return b
}

// ReadStdin reads up to maxBytes from r, drains any remaining input, and
// returns the result with any leading UTF-8 BOM stripped.
func ReadStdin(r io.Reader, maxBytes int) []byte {
	buf := make([]byte, maxBytes)
	n, _ := io.ReadFull(r, buf)
	// Drain remaining input so the hook process doesn't block.
	if n == maxBytes {
		io.Copy(io.Discard, r) //nolint:errcheck
	}
	return StripBOM(buf[:n])
}
