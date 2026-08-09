// 文件用途：提供文本清洗、乱码识别和编码兼容工具。
// 核心逻辑：统一处理输入文本的规范化和异常字符，保证持久化与响应一致。

package textutil

// TruncateRunes

func TruncateRunes(s string, max int) string {
	if max <= 0 {
		return ""
	}
	runes := []rune(s)
	if len(runes) <= max {
		return s
	}
	return string(runes[:max])
}

// TruncateRunesWithSuffix

func TruncateRunesWithSuffix(s string, max int, suffix string) string {
	if max <= 0 {
		return ""
	}
	runes := []rune(s)
	if len(runes) <= max {
		return s
	}
	return string(runes[:max]) + suffix
}
