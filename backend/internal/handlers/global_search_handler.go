// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

type GlobalSearchHandler struct {
	db         *gorm.DB
	msgService *services.MessageService
}

func NewGlobalSearchHandler(db *gorm.DB, msgService *services.MessageService) *GlobalSearchHandler {
	return &GlobalSearchHandler{db: db, msgService: msgService}
}

type globalSearchChatRow struct {
	UserChatID     uint64     `gorm:"column:user_chat_id"`
	ChatID         uint64     `gorm:"column:chat_id"`
	ChatUUID       string     `gorm:"column:chat_uuid"`
	Type           int8       `gorm:"column:type"`
	Name           string     `gorm:"column:name"`
	Avatar         string     `gorm:"column:avatar"`
	Description    string     `gorm:"column:description"`
	Username       string     `gorm:"column:username"`
	MemberCount    int        `gorm:"column:member_count"`
	LastMsgText    string     `gorm:"column:last_msg_text"`
	LastMsgType    int        `gorm:"column:last_msg_type"`
	LastMsgTime    *time.Time `gorm:"column:last_msg_time"`
	LastMsgSeq     uint64     `gorm:"column:last_msg_seq"`
	UnreadCount    int        `gorm:"column:unread_count"`
	IsPinned       bool       `gorm:"column:is_pinned"`
	IsMuted        bool       `gorm:"column:is_muted"`
	TargetID       uint64     `gorm:"column:target_id"`
	TargetUUID     string     `gorm:"column:target_uuid"`
	TargetName     string     `gorm:"column:target_name"`
	TargetUsername string     `gorm:"column:target_username"`
	TargetAvatar   string     `gorm:"column:target_avatar"`
	Remark         string     `gorm:"column:remark"`
}

func (h *GlobalSearchHandler) Search(c *gin.Context) {
	userUUID := c.GetString("user_id")
	keyword := strings.TrimSpace(c.Query("keyword"))
	scope := strings.TrimSpace(c.DefaultQuery("scope", "all"))
	if keyword == "" {
		response.BadRequest(c, "请输入搜索关键词")
		return
	}
	limit := parseSearchLimit(c.DefaultQuery("limit", "8"), 1, 20, 8)
	page := parseSearchPage(c.DefaultQuery("page", "1"))
	offset := (page - 1) * limit
	windowLimit := limit + offset + 1

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Error(c, http.StatusUnauthorized, "请先登录")
		return
	}
	result := gin.H{
		"keyword":  keyword,
		"page":     page,
		"limit":    limit,
		"contacts": []gin.H{},
		"chats":    []gin.H{},
		"messages": []gin.H{},
		"files":    []gin.H{},
		"has_more": gin.H{
			"contacts": false,
			"chats":    false,
			"messages": false,
			"files":    false,
		},
	}
	hasMore := result["has_more"].(gin.H)
	if scope == "all" || scope == "contact" || scope == "contacts" {
		items := h.searchContacts(user.ID, keyword, windowLimit)
		result["contacts"], hasMore["contacts"] = sliceSearchItems(items, offset, limit)
	}
	chatRows := h.visibleChats(user.ID)
	if scope == "all" || scope == "chat" || scope == "chats" {
		items := filterGlobalSearchChats(chatRows, keyword, windowLimit)
		result["chats"], hasMore["chats"] = sliceSearchItems(items, offset, limit)
	}
	if scope == "all" || scope == "message" || scope == "messages" || scope == "file" || scope == "files" {
		messages, files := h.searchChatContent(c.Request.Context(), user.UUID, chatRows, keyword, windowLimit)
		if scope == "all" || scope == "message" || scope == "messages" {
			result["messages"], hasMore["messages"] = sliceSearchItems(messages, offset, limit)
		}
		if scope == "all" || scope == "file" || scope == "files" {
			result["files"], hasMore["files"] = sliceSearchItems(files, offset, limit)
		}
	}
	response.Success(c, result)
}

func (h *GlobalSearchHandler) searchContacts(userID uint64, keyword string, limit int) []gin.H {
	like := "%" + keyword + "%"
	type row struct {
		UserID        uint64 `gorm:"column:user_id"`
		UUID          string `gorm:"column:uuid"`
		Nickname      string `gorm:"column:nickname"`
		Username      string `gorm:"column:username"`
		Avatar        string `gorm:"column:avatar"`
		Bio           string `gorm:"column:bio"`
		Remark        string `gorm:"column:remark"`
		EmojiAvatar   string `gorm:"column:emoji_avatar"`
		NicknameColor string `gorm:"column:nickname_color"`
	}
	var rows []row
	h.db.Table("contacts").
		Select("users.id AS user_id, users.uuid, users.nickname, users.username, users.avatar, users.bio, contacts.remark, users.emoji_avatar, users.nickname_color").
		Joins("JOIN users ON users.id = contacts.contact_user_id AND users.deleted_at IS NULL").
		Where("contacts.user_id = ? AND contacts.status = 1", userID).
		Where("(contacts.remark LIKE ? OR users.nickname LIKE ? OR users.username LIKE ?)", like, like, like).
		Order("CASE WHEN contacts.remark = '' OR contacts.remark IS NULL THEN 1 ELSE 0 END ASC").
		Order("contacts.updated_at DESC").
		Limit(limit).
		Scan(&rows)
	userIDs := make([]uint64, 0, len(rows))
	for _, row := range rows {
		userIDs = append(userIDs, row.UserID)
	}
	vipSummaries := buildUserVipSummaries(h.db, userIDs)
	items := make([]gin.H, 0, len(rows))
	for _, row := range rows {
		title := row.Remark
		if strings.TrimSpace(title) == "" {
			title = row.Nickname
		}
		items = append(items, gin.H{
			"id":             row.UUID,
			"type":           "contact",
			"title":          title,
			"subtitle":       row.Username,
			"avatar":         row.Avatar,
			"bio":            row.Bio,
			"highlight":      highlightBestSnippet(keyword, title, row.Username, row.Bio),
			"emoji_avatar":   row.EmojiAvatar,
			"nickname_color": row.NicknameColor,
			"vip":            vipSummaries[row.UserID],
		})
	}
	return items
}

func (h *GlobalSearchHandler) visibleChats(userID uint64) []globalSearchChatRow {
	var rows []globalSearchChatRow
	h.db.Table("user_chats uc").
		Select(` 			uc.id AS user_chat_id, uc.chat_id, c.uuid AS chat_uuid, c.type, c.name, c.avatar, c.description, c.username, c.member_count, uc.last_msg_text, uc.last_msg_type, uc.last_msg_time, uc.last_msg_seq, uc.unread_count, uc.is_pinned, uc.is_muted, uc.target_id, tu.uuid AS target_uuid, tu.nickname AS target_name, tu.username AS target_username, tu.avatar AS target_avatar, contacts.remark 		`).
		Joins("JOIN chats c ON c.id = uc.chat_id AND c.deleted_at IS NULL").
		Joins("LEFT JOIN users tu ON tu.id = uc.target_id AND tu.deleted_at IS NULL").
		Joins("LEFT JOIN contacts ON contacts.user_id = uc.user_id AND contacts.contact_user_id = uc.target_id AND contacts.status = 1").
		Where("uc.user_id = ?", userID).
		Order("uc.is_pinned DESC, uc.sort_time DESC").
		Limit(200).
		Scan(&rows)
	return rows
}

func filterGlobalSearchChats(rows []globalSearchChatRow, keyword string, limit int) []gin.H {
	query := strings.ToLower(keyword)
	items := make([]gin.H, 0, limit)
	for _, row := range rows {
		title := row.Name
		subtitle := row.Description
		avatar := row.Avatar
		if row.Type == 1 {
			title = row.TargetName
			if strings.TrimSpace(row.Remark) != "" {
				title = row.Remark
			}
			subtitle = row.TargetUsername
			if row.TargetAvatar != "" {
				avatar = row.TargetAvatar
			}
		}
		haystack := strings.ToLower(strings.Join([]string{
			title,
			row.Name,
			row.Username,
			row.TargetName,
			row.TargetUsername,
			row.Remark,
			row.Description,
		}, " "))
		if !strings.Contains(haystack, query) {
			continue
		}
		items = append(items, gin.H{
			"id":             row.ChatUUID,
			"type":           chatTypeName(row.Type),
			"title":          title,
			"subtitle":       subtitle,
			"avatar":         avatar,
			"member_count":   row.MemberCount,
			"unread_count":   row.UnreadCount,
			"is_pinned":      row.IsPinned,
			"is_muted":       row.IsMuted,
			"last_msg_text":  normalizeStoredChatPreviewText(row.LastMsgText, row.LastMsgType),
			"last_msg_time":  optionalTimeValue(row.LastMsgTime),
			"last_msg_seq":   row.LastMsgSeq,
			"target_user_id": row.TargetUUID,
			"highlight":      highlightBestSnippet(keyword, title, row.Username, row.TargetUsername, row.Remark, row.Description),
		})
		if len(items) >= limit {
			break
		}
	}
	return items
}

func (h *GlobalSearchHandler) searchChatContent(ctx context.Context, userUUID string, chats []globalSearchChatRow, keyword string, limit int) ([]gin.H, []gin.H) {
	if h.msgService == nil || len(chats) == 0 {
		return []gin.H{}, []gin.H{}
	}
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	messages := make([]gin.H, 0, limit)
	files := make([]gin.H, 0, limit)
	for _, chat := range chats {
		if len(messages) >= limit && len(files) >= limit {
			break
		}
		found, err := h.msgService.SearchMessagesForUser(ctx, chat.ChatUUID, userUUID, keyword, 6)
		if err != nil {
			continue
		}
		for _, msg := range found {
			if msg == nil {
				continue
			}
			title := chat.Name
			if chat.Type == 1 {
				title = chat.TargetName
				if strings.TrimSpace(chat.Remark) != "" {
					title = chat.Remark
				}
			}
			if len(messages) < limit {
				messages = append(messages, gin.H{
					"id":          msg.MsgID,
					"type":        "message",
					"title":       title,
					"subtitle":    msg.SenderName,
					"chat_id":     msg.ChatID,
					"chat_name":   title,
					"chat_type":   chat.Type,
					"message_id":  msg.MsgID,
					"seq":         msg.Seq,
					"content":     msg.Content,
					"highlight":   highlightSnippet(msg.Content.Text, keyword),
					"sender_id":   msg.SenderID,
					"sender_name": msg.SenderName,
					"created_at":  msg.CreatedAt,
				})
			}
		}
		if len(files) < limit {
			fileMessages, err := h.msgService.SearchFiles(ctx, chat.ChatUUID, userUUID, keyword, limit-len(files))
			if err == nil {
				title := chat.Name
				if chat.Type == 1 {
					title = chat.TargetName
					if strings.TrimSpace(chat.Remark) != "" {
						title = chat.Remark
					}
				}
				for _, msg := range fileMessages {
					if msg == nil || msg.Content.File == nil {
						continue
					}
					files = append(files, gin.H{
						"id":         msg.MsgID,
						"type":       "file",
						"title":      msg.Content.File.Name,
						"subtitle":   title,
						"chat_id":    msg.ChatID,
						"chat_name":  title,
						"chat_type":  chat.Type,
						"message_id": msg.MsgID,
						"seq":        msg.Seq,
						"highlight":  highlightSnippet(msg.Content.File.Name, keyword),
						"size":       msg.Content.File.Size,
						"mime_type":  msg.Content.File.MimeType,
						"url":        msg.Content.File.URL,
						"created_at": msg.CreatedAt,
					})
				}
			}
		}
	}
	return messages, files
}

func parseSearchLimit(raw string, min int, max int, fallback int) int {
	n := fallback
	if parsed, err := strconv.Atoi(raw); err == nil {
		n = parsed
	}
	if n < min {
		return min
	}
	if n > max {
		return max
	}
	return n
}

func parseSearchPage(raw string) int {
	page, err := strconv.Atoi(raw)
	if err != nil || page < 1 {
		return 1
	}
	if page > 50 {
		return 50
	}
	return page
}

func sliceSearchItems(items []gin.H, offset int, limit int) ([]gin.H, bool) {
	if limit <= 0 {
		return []gin.H{}, false
	}
	if offset >= len(items) {
		return []gin.H{}, false
	}
	end := offset + limit
	hasMore := len(items) > end
	if end > len(items) {
		end = len(items)
	}
	return items[offset:end], hasMore
}

func highlightSnippet(text string, keyword string) gin.H {
	text = strings.TrimSpace(text)
	keyword = strings.TrimSpace(keyword)
	if text == "" {
		return gin.H{"text": "", "start": -1, "end": -1}
	}
	if keyword == "" {
		return gin.H{"text": trimRunes(text, 80), "start": -1, "end": -1}
	}
	lowerText := strings.ToLower(text)
	lowerKeyword := strings.ToLower(keyword)
	byteStart := strings.Index(lowerText, lowerKeyword)
	if byteStart < 0 {
		return gin.H{"text": trimRunes(text, 80), "start": -1, "end": -1}
	}
	byteEnd := byteStart + len(keyword)
	if byteEnd > len(text) {
		byteEnd = len(text)
	}
	matchStartRune := utf8.RuneCountInString(text[:byteStart])
	matchRuneLen := utf8.RuneCountInString(text[byteStart:byteEnd])
	if matchRuneLen <= 0 {
		matchRuneLen = len([]rune(keyword))
	}
	runes := []rune(text)
	snippetStart := matchStartRune - 24
	if snippetStart < 0 {
		snippetStart = 0
	}
	snippetEnd := matchStartRune + matchRuneLen + 48
	if snippetEnd > len(runes) {
		snippetEnd = len(runes)
	}
	snippet := string(runes[snippetStart:snippetEnd])
	prefix := ""
	suffix := ""
	if snippetStart > 0 {
		prefix = "..."
	}
	if snippetEnd < len(runes) {
		suffix = "..."
	}
	start := matchStartRune - snippetStart + len([]rune(prefix))
	end := start + matchRuneLen
	return gin.H{
		"text":  prefix + snippet + suffix,
		"start": start,
		"end":   end,
	}
}

func highlightBestSnippet(keyword string, candidates ...string) gin.H {
	for _, candidate := range candidates {
		if strings.TrimSpace(candidate) == "" {
			continue
		}
		highlight := highlightSnippet(candidate, keyword)
		if start, ok := highlight["start"].(int); ok && start >= 0 {
			return highlight
		}
	}
	for _, candidate := range candidates {
		if strings.TrimSpace(candidate) != "" {
			return highlightSnippet(candidate, keyword)
		}
	}
	return gin.H{"text": "", "start": -1, "end": -1}
}

func trimRunes(text string, max int) string {
	runes := []rune(text)
	if max <= 0 || len(runes) <= max {
		return text
	}
	return string(runes[:max]) + "..."
}

func chatTypeName(t int8) string {
	switch t {
	case 1:
		return "private"
	case 2:
		return "group"
	case 3:
		return "channel"
	default:
		return "chat"
	}
}
