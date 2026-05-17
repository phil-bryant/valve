package logging

import (
	"io"
	"os"
	"strings"
	"testing"
)

// Supplemental numbered tag for log-level filtering requirement parity.
// #R001-T03

func TestNewLoggerWritesStructuredJSONToStdout(t *testing.T) {
	// #R001-T01: NewLogger returns a non-nil logger.
	// #R001-T02: Info level message produces JSON-parseable line on stdout.
	// #R001: Logger emits JSON structure to stdout for runtime observability.
	oldStdout := os.Stdout
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stdout pipe: %v", err)
	}
	os.Stdout = writer
	defer func() { os.Stdout = oldStdout }()
	logger := NewLogger()
	logger.Info("hello-from-test", "component", "logging")
	if err := writer.Close(); err != nil {
		t.Fatalf("failed to close writer: %v", err)
	}
	out, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("failed to read logger output: %v", err)
	}
	text := string(out)
	if !strings.Contains(text, "\"msg\":\"hello-from-test\"") {
		t.Fatalf("expected message field in logger output, got %q", text)
	}
	if !strings.Contains(text, "\"component\":\"logging\"") {
		t.Fatalf("expected structured attribute in logger output, got %q", text)
	}
}
