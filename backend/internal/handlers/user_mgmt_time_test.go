package handlers

import (
	"testing"
	"time"
)

func TestFormatAdminTimeConvertsUTCToShanghai(t *testing.T) {
	t.Parallel()

	input := time.Date(2026, time.July, 28, 14, 6, 3, 0, time.UTC)
	if got, want := formatAdminTime(input), "2026-07-28 22:06:03"; got != want {
		t.Fatalf("formatAdminTime() = %q, want %q", got, want)
	}
}

func TestFormatAdminTimeReturnsEmptyForZeroValue(t *testing.T) {
	t.Parallel()

	if got := formatAdminTime(time.Time{}); got != "" {
		t.Fatalf("formatAdminTime(zero) = %q, want empty string", got)
	}
}
