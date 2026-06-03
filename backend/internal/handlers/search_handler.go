package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"gaoranim/internal/services"
)

// SearchHandler 全局消息搜索
type SearchHandler struct {
	searchSvc  *services.SearchService
	msgService *services.MessageService
}

func NewSearchHandler(searchSvc *services.SearchService, msgService *services.MessageService) *SearchHandler {
	return &SearchHandler{searchSvc: searchSvc, msgService: msgService}
}

// SearchMessages GET /api/v1/message/search?q=关键词&page=1&size=20
func (h *SearchHandler) SearchMessages(c *gin.Context) {
	keyword := strings.TrimSpace(c.Query("q"))
	if keyword == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "搜索关键词不能为空"})
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	size, _ := strconv.Atoi(c.DefaultQuery("size", "20"))
	if page <= 0 { page = 1 }
	if size <= 0 || size > 50 { size = 20 }

	ctx := c.Request.Context()

	// ES可用走ES，否则降级MongoDB
	if h.searchSvc.IsEnabled() {
		results, total, err := h.searchSvc.Search(ctx, keyword, "", page, size)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "搜索失败"})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"total": total, "page": page, "size": size,
			"results": results, "engine": "elasticsearch",
		})
		return
	}

	// 降级：MongoDB正则搜索
	messages, err := h.msgService.SearchMessagesGlobal(ctx, keyword, size)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "搜索失败"})
		return
	}
	results := make([]gin.H, 0, len(messages))
	for _, msg := range messages {
		results = append(results, gin.H{
			"msg_id": msg.MsgID, "chat_id": msg.ChatID,
			"sender_id": msg.SenderID, "sender_name": msg.SenderName,
			"content": msg.Content.Text, "highlight": msg.Content.Text,
			"sent_at": msg.CreatedAt,
		})
	}
	c.JSON(http.StatusOK, gin.H{
		"total": len(results), "page": page, "size": size,
		"results": results, "engine": "mongodb",
	})
}
