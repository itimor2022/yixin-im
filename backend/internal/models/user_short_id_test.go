package models

import "testing"

func TestBuildUserShortID(t *testing.T) {
	got := BuildUserShortID(123)
	want := UserShortIDBase + 123
	if got != want {
		t.Fatalf("short id mismatch: want=%d got=%d", want, got)
	}
}

func TestParseUserShortIDKeyword(t *testing.T) {
	tests := []struct {
		name   string
		input  string
		wantOK bool
		wantID uint64
	}{
		{name: "ok", input: "100000123", wantOK: true, wantID: 100000123},
		{name: "trim ok", input: " 100000124 ", wantOK: true, wantID: 100000124},
		{name: "non digit", input: "abc123", wantOK: false, wantID: 0},
		{name: "empty", input: " ", wantOK: false, wantID: 0},
		{name: "zero", input: "0", wantOK: false, wantID: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := ParseUserShortIDKeyword(tt.input)
			if ok != tt.wantOK {
				t.Fatalf("ok mismatch: want=%v got=%v id=%d", tt.wantOK, ok, got)
			}
			if got != tt.wantID {
				t.Fatalf("id mismatch: want=%d got=%d", tt.wantID, got)
			}
		})
	}
}
