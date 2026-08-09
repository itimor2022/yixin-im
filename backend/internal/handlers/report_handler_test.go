// 文件用途：验证 report_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"strings"
	"testing"
)

func TestNormalizeCreateReportRequest(t *testing.T) {
	request := CreateReportRequest{
		TargetID:    " 11111111-1111-1111-1111-111111111111 ",
		TargetType:  " user ",
		ChatID:      " 22222222-2222-2222-2222-222222222222 ",
		Reason:      " spam ",
		Description: " details ",
	}
	if message := normalizeCreateReportRequest(&request); message != "" {
		t.Fatalf("unexpected validation error: %s", message)
	}
	if request.TargetID != "11111111-1111-1111-1111-111111111111" || request.TargetType != "user" || request.ChatID != "22222222-2222-2222-2222-222222222222" || request.Description != "details" {
		t.Fatalf("request was not normalized: %+v", request)
	}
	for name, invalid := range map[string]CreateReportRequest{
		"missing target": {TargetType: "user", Reason: "spam"},
		"bad target id":  {TargetID: "target", TargetType: "user", Reason: "spam"},
		"bad chat id":    {TargetID: "11111111-1111-1111-1111-111111111111", TargetType: "message", ChatID: "chat", Reason: "spam"},
		"bad reason":     {TargetID: "11111111-1111-1111-1111-111111111111", TargetType: "user", Reason: "false_info"},
		"long details":   {TargetID: "11111111-1111-1111-1111-111111111111", TargetType: "user", Reason: "spam", Description: strings.Repeat("界", 501)},
	} {
		t.Run(name, func(t *testing.T) {
			if message := normalizeCreateReportRequest(&invalid); message == "" {
				t.Fatalf("invalid request was accepted: %+v", invalid)
			}
		})
	}
}

func TestShortReportTargetHandlesLegacyValues(t *testing.T) {
	if got := shortReportTarget("abc"); got != "abc" {
		t.Fatalf("short target=%q", got)
	}
	if got := shortReportTarget("1234567890"); got != "12345678" {
		t.Fatalf("truncated target=%q", got)
	}
}
