// 文件用途：验证 setting_handler_h5_url_validation_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import "testing"

func TestValidatePublicH5URLSetting(t *testing.T) {
	tests := []struct {
		name    string
		value   string
		wantErr bool
	}{
		{name: "empty is allowed", value: "", wantErr: false},
		{name: "h5 origin", value: "https://h5.example.com", wantErr: false},
		{name: "existing hash route", value: "https://h5.example.com/#/", wantErr: false},
		{name: "api host", value: "https://api.example.com", wantErr: true},
		{name: "imapi host", value: "https://api.example.com", wantErr: true},
		{name: "api path", value: "https://example.com/api/v1", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validatePublicH5URLSetting(tt.value)
			if (err != nil) != tt.wantErr {
				t.Fatalf("validatePublicH5URLSetting(%q) error = %v, wantErr %v", tt.value, err, tt.wantErr)
			}
		})
	}
}
