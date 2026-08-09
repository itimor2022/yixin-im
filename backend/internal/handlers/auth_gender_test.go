// 文件用途：验证 auth_gender_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import "testing"

func TestResolveRegisterGender(t *testing.T) {
	tests := []struct {
		name     string
		value    string
		required bool
		want     string
		valid    bool
	}{
		{name: "required missing", required: true, valid: false},
		{name: "optional missing", required: false, want: "unknown", valid: true},
		{name: "male", value: "male", required: true, want: "male", valid: true},
		{name: "female alias", value: "女", required: true, want: "female", valid: true},
		{name: "unsupported", value: "other", required: false, valid: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, valid := resolveRegisterGender(tt.value, tt.required)
			if got != tt.want || valid != tt.valid {
				t.Fatalf("resolveRegisterGender(%q, %v) = (%q, %v), want(%q, %v)", tt.value, tt.required, got, valid, tt.want, tt.valid)
			}
		})
	}
}

func TestNormalizeRegisterPhoneCredentials(t *testing.T) {
	phone, code, provided, valid := normalizeRegisterPhoneCredentials("13800138000", "123456")
	if phone != "13800138000" || code != "123456" || !provided || !valid {
		t.Fatalf("valid credentials normalized to(%q,%q,%v,%v)", phone, code, provided, valid)
	}

	_, _, provided, valid = normalizeRegisterPhoneCredentials("123", "")
	if !provided || valid {
		t.Fatal("an invalid supplied phone must not be treated as omitted")
	}

	_, _, provided, valid = normalizeRegisterPhoneCredentials("13800138000", "ABC123")
	if !provided || valid {
		t.Fatal("a registration SMS code must contain exactly six digits")
	}

	_, _, provided, valid = normalizeRegisterPhoneCredentials("", "")
	if provided || !valid {
		t.Fatal("fully omitted optional phone credentials should remain valid")
	}
	if registerSMSCodeKey("13800138000") != "auth:register:sms:13800138000" {
		t.Fatal("registration SMS key must be isolated from bind/reset keys")
	}
}

func TestNormalizeRegisterEmailCredentials(t *testing.T) {
	email, code, provided, valid := normalizeRegisterEmailCredentials("QA.User@Example.com", "123456")
	if email != "qa.user@example.com" || code != "123456" || !provided || !valid {
		t.Fatalf("valid email credentials normalized to(%q,%q,%v,%v)", email, code, provided, valid)
	}

	_, _, provided, valid = normalizeRegisterEmailCredentials("invalid", "123456")
	if !provided || valid {
		t.Fatal("an invalid supplied email must not be treated as omitted")
	}

	_, _, provided, valid = normalizeRegisterEmailCredentials("", "")
	if provided || !valid {
		t.Fatal("fully omitted optional email credentials should remain valid")
	}
	if registerEmailCodeKey("qa@example.com") != "auth:register:email:qa@example.com" {
		t.Fatal("registration email key must be isolated from other verification keys")
	}
}
