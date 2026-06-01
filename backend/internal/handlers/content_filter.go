package handlers

import (
	"regexp"
	"strings"

	"gaoranim/internal/models"

	"gorm.io/gorm"
)

// filterContentWithDB 对文本内容进行违禁词过滤（包级共享，供各 handler 调用）
//
// 返回：(过滤/替换后的内容, 是否被拦截)
//   - 级别 1（警告）：仅记录命中次数，放行原文
//   - 级别 2（替换）：大小写不敏感替换为 replacement 或 *
//   - 级别 3（拦截）：直接返回 blocked=true，调用方应拒绝请求
func filterContentWithDB(db *gorm.DB, content string) (string, bool) {
	var bannedWords []models.BannedWord
	db.Where("status = 1").Find(&bannedWords)
	if len(bannedWords) == 0 {
		return content, false
	}

	filtered := content
	lowerContent := strings.ToLower(content)

	for _, bw := range bannedWords {
		// 空 Word 会导致 Contains 恒为 true，跳过
		if strings.TrimSpace(bw.Word) == "" {
			continue
		}
		lowerWord := strings.ToLower(bw.Word)
		if !strings.Contains(lowerContent, lowerWord) {
			continue
		}

		// 命中：更新统计
		db.Model(&bw).UpdateColumn("hit_count", gorm.Expr("hit_count + 1"))

		switch bw.Level {
		case models.BannedLevelBlock:
			return content, true
		case models.BannedLevelFilter:
			replacement := bw.Replacement
			if replacement == "" {
				replacement = strings.Repeat("*", len([]rune(bw.Word)))
			}
			re, err := regexp.Compile("(?i)" + regexp.QuoteMeta(bw.Word))
			if err == nil {
				filtered = re.ReplaceAllString(filtered, replacement)
				lowerContent = strings.ToLower(filtered)
			}
		case models.BannedLevelWarn:
			// 仅记录 hit_count，不阻止
		default:
			// 未知级别同警告处理
		}
	}

	return filtered, false
}
