package handlers

import "testing"

func TestParseSettingBoolValue(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		input     interface{}
		want      bool
		wantError bool
	}{
		{name: "bool true", input: true, want: true},
		{name: "bool false", input: false, want: false},
		{name: "string true", input: "true", want: true},
		{name: "string on", input: "on", want: true},
		{name: "string one", input: "1", want: true},
		{name: "string false", input: "false", want: false},
		{name: "string empty", input: "", want: false},
		{name: "float one", input: float64(1), want: true},
		{name: "float zero", input: float64(0), want: false},
		{name: "string invalid", input: "abc", wantError: true},
		{name: "unsupported type", input: 1, wantError: true},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			got, err := parseSettingBoolValue(tc.input)
			if tc.wantError {
				if err == nil {
					t.Fatalf("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Fatalf("parseSettingBoolValue(%v)=%v, want %v", tc.input, got, tc.want)
			}
		})
	}
}

func TestNormalizeSettingInputValue(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		input interface{}
		want  string
	}{
		{name: "trim string", input: "  value  ", want: "value"},
		{name: "bool true", input: true, want: "true"},
		{name: "bool false", input: false, want: "false"},
		{name: "float to int", input: float64(12), want: "12"},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			got := normalizeSettingInputValue(tc.input)
			if got != tc.want {
				t.Fatalf("normalizeSettingInputValue(%v)=%q, want %q", tc.input, got, tc.want)
			}
		})
	}

	t.Run("object marshal", func(t *testing.T) {
		t.Parallel()
		got := normalizeSettingInputValue(map[string]interface{}{"a": 1})
		if got == "" {
			t.Fatalf("expected marshaled json, got empty string")
		}
	})
}

func TestValidateFCMPushConfig(t *testing.T) {
	t.Parallel()

	const validJSON = `{
		"type":"service_account",
		"project_id":"timi-9125c",
		"client_email":"firebase-adminsdk@test.iam.gserviceaccount.com",
		"private_key":"-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n"
	}`

	tests := []struct {
		name      string
		projectID string
		json      string
		wantError bool
	}{
		{
			name:      "valid",
			projectID: "timi-9125c",
			json:      validJSON,
			wantError: false,
		},
		{
			name:      "mobilesdk_app_id_should_fail",
			projectID: "1:462874705402:android:1ee89f88de6ab550afb843",
			json:      validJSON,
			wantError: true,
		},
		{
			name:      "missing_project_id_in_json",
			projectID: "timi-9125c",
			json: `{
				"type":"service_account",
				"client_email":"firebase-adminsdk@test.iam.gserviceaccount.com",
				"private_key":"-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n"
			}`,
			wantError: true,
		},
		{
			name:      "project_id_mismatch",
			projectID: "another-project",
			json:      validJSON,
			wantError: true,
		},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			err := validateFCMPushConfig(tc.projectID, tc.json)
			if tc.wantError && err == nil {
				t.Fatalf("expected error, got nil")
			}
			if !tc.wantError && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}
