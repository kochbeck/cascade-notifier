package protocol

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

func roundTrip(t *testing.T, hookType, payload string) Message {
	t.Helper()
	var buf bytes.Buffer
	if err := Encode(&buf, hookType, payload); err != nil {
		t.Fatalf("Encode: %v", err)
	}
	msg, err := Decode(&buf)
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	return msg
}

func TestRoundTrip_Basic(t *testing.T) {
	msg := roundTrip(t, "pcr", `{"tool_info":{"response":"done"}}`)
	if msg.HookType != "pcr" {
		t.Errorf("HookType = %q, want pcr", msg.HookType)
	}
	if msg.Payload != `{"tool_info":{"response":"done"}}` {
		t.Errorf("Payload = %q", msg.Payload)
	}
}

func TestRoundTrip_PRC(t *testing.T) {
	msg := roundTrip(t, "prc", `{"tool_info":{"command_line":"sudo apt update"}}`)
	if msg.HookType != "prc" {
		t.Errorf("HookType = %q, want prc", msg.HookType)
	}
}

func TestRoundTrip_EmbeddedNewlines(t *testing.T) {
	payload := "line1\nline2\r\nline3\rend"
	msg := roundTrip(t, "pcr", payload)
	if msg.Payload != payload {
		t.Errorf("payload with embedded newlines corrupted: got %q", msg.Payload)
	}
}

func TestRoundTrip_MultibyteUTF8(t *testing.T) {
	payload := "Hello \u4e16\u754c \U0001F600 \u0645\u0631\u062d\u0628\u0627"
	msg := roundTrip(t, "pcr", payload)
	if msg.Payload != payload {
		t.Errorf("UTF-8 payload corrupted: got %q", msg.Payload)
	}
}

func TestRoundTrip_ZeroLength(t *testing.T) {
	msg := roundTrip(t, "pcr", "")
	// Empty payload round-trips; hooktype is empty too because body is "pcr\t"
	if msg.HookType != "pcr" {
		t.Errorf("HookType = %q, want pcr", msg.HookType)
	}
	if msg.Payload != "" {
		t.Errorf("Payload = %q, want empty", msg.Payload)
	}
}

func TestRoundTrip_MaxSizePayload(t *testing.T) {
	payload := strings.Repeat("x", 8192)
	msg := roundTrip(t, "pcr", payload)
	if len(msg.Payload) != 8192 {
		t.Errorf("payload length = %d, want 8192", len(msg.Payload))
	}
}

func TestDecode_TruncatedLengthHeader(t *testing.T) {
	// Write only 3 bytes (incomplete uint32 header).
	r := bytes.NewReader([]byte{0x00, 0x00, 0x00})
	_, err := Decode(r)
	if err == nil {
		t.Error("expected error for truncated header, got nil")
	}
}

func TestDecode_MalformedNoTab(t *testing.T) {
	var buf bytes.Buffer
	body := "notabseparator"
	length := uint32(len(body))
	buf.WriteByte(byte(length >> 24))
	buf.WriteByte(byte(length >> 16))
	buf.WriteByte(byte(length >> 8))
	buf.WriteByte(byte(length))
	buf.WriteString(body)
	_, err := Decode(&buf)
	if err == nil {
		t.Error("expected error for missing tab, got nil")
	}
}

func TestStripBOM(t *testing.T) {
	withBOM := append(utf8BOM, []byte(`{"key":"value"}`)...)
	stripped := StripBOM(withBOM)
	if bytes.HasPrefix(stripped, utf8BOM) {
		t.Error("BOM was not stripped")
	}
	if string(stripped) != `{"key":"value"}` {
		t.Errorf("unexpected result after BOM strip: %q", stripped)
	}
}

func TestStripBOM_NoBOM(t *testing.T) {
	input := []byte(`{"key":"value"}`)
	result := StripBOM(input)
	if !bytes.Equal(result, input) {
		t.Errorf("StripBOM modified input without BOM")
	}
}

func TestReadStdin_UnderLimit(t *testing.T) {
	data := []byte(`{"hello":"world"}`)
	r := bytes.NewReader(data)
	result := ReadStdin(r, 8192)
	if !bytes.Equal(result, data) {
		t.Errorf("ReadStdin under limit: got %q, want %q", result, data)
	}
}

func TestReadStdin_OverLimit(t *testing.T) {
	data := bytes.Repeat([]byte("x"), 10000)
	r := bytes.NewReader(data)
	result := ReadStdin(r, 8192)
	if len(result) != 8192 {
		t.Errorf("ReadStdin over limit: got %d bytes, want 8192", len(result))
	}
}

func TestReadStdin_DrainRemainder(t *testing.T) {
	// Verify that after ReadStdin the reader is fully consumed (drained).
	data := bytes.Repeat([]byte("y"), 10000)
	r := bytes.NewReader(data)
	ReadStdin(r, 100)
	remaining, _ := io.ReadAll(r)
	if len(remaining) != 0 {
		t.Errorf("ReadStdin did not drain remainder: %d bytes left", len(remaining))
	}
}

func TestReadStdin_StripsBOM(t *testing.T) {
	data := append(utf8BOM, []byte(`{"k":"v"}`)...)
	r := bytes.NewReader(data)
	result := ReadStdin(r, 8192)
	if bytes.HasPrefix(result, utf8BOM) {
		t.Error("ReadStdin did not strip BOM")
	}
}
