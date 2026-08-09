// 文件用途：验证 service_operation_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"errors"
	"reflect"
	"testing"
)

func TestNormalizeQuickReply(t *testing.T) {
	category, title, content, shortcut, keywords, err := normalizeQuickReply(ServiceQuickReplyInput{
		Title: "  欢迎语  ", Content: "  您好，请问有什么可以帮您？  ", Shortcut: " /hello ", Keywords: " 欢迎,您好 ",
	})
	if err != nil {
		t.Fatalf("normalizeQuickReply returned error: %v", err)
	}
	if category != "通用" || title != "欢迎语" || content != "您好，请问有什么可以帮您？" || shortcut != "/hello" || keywords != "欢迎,您好" {
		t.Fatalf("unexpected normalized reply: %q %q %q %q %q", category, title, content, shortcut, keywords)
	}

	_, _, _, _, _, err = normalizeQuickReply(ServiceQuickReplyInput{Title: "缺少内容"})
	if !errors.Is(err, ErrServiceInvalidTransition) {
		t.Fatalf("expected validation error, got %v", err)
	}
}

func TestNormalizeServiceTags(t *testing.T) {
	tags, err := normalizeServiceTags([]string{" 高意向 ", "VIP", "高意向", ""})
	if err != nil {
		t.Fatalf("normalizeServiceTags returned error: %v", err)
	}
	if !reflect.DeepEqual(tags, []string{"高意向", "VIP"}) {
		t.Fatalf("unexpected tags: %#v", tags)
	}
	tooMany := []string{"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"}
	if _, err := normalizeServiceTags(tooMany); !errors.Is(err, ErrServiceInvalidTransition) {
		t.Fatalf("expected too-many-tags validation error, got %v", err)
	}
}
