// 文件用途：实现 backend 目录中的 response.go 模块。
// 核心逻辑：围绕本文件的类型和函数完成输入处理、状态转换或辅助计算。

package response

import (
	"github.com/gin-gonic/gin"
	"net/http"
)

// Response 统一响应结构
type Response struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// 响应码定义
const (
	CodeSuccess                        = 0
	CodePhoneBindRequired              = 1002
	CodeAccountBanned                  = 1008
	CodeBadRequest                     = 400
	CodeUnauthorized                   = 401
	CodeForbidden                      = 403
	CodeNotFound                       = 404
	CodeTooMany                        = 429
	CodeDirectUploadRateLimited        = 1429
	CodeDirectUploadStorageUnavailable = 1430
	CodeDirectUploadDisabled           = 1431
	CodeDirectUploadPlatformDisabled   = 1432
	CodeDirectUploadRolloutExcluded    = 1433
	CodeServerError                    = 500
)

// Success 成功响应
func Success(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, Response{
		Code:    CodeSuccess,
		Message: "success",
		Data:    data,
	})
}

// SuccessWithMessage 带消息的成功响应
func SuccessWithMessage(c *gin.Context, message string, data interface{}) {
	c.JSON(http.StatusOK, Response{
		Code:    CodeSuccess,
		Message: message,
		Data:    data,
	})
}

// Error 错误响应
func Error(c *gin.Context, code int, message string) {
	c.JSON(http.StatusOK, Response{
		Code:    code,
		Message: message,
	})
}

func ErrorWithData(c *gin.Context, code int, message string, data interface{}) {
	c.JSON(http.StatusOK, Response{
		Code:    code,
		Message: message,
		Data:    data,
	})
}

// BadRequest 400错误
func BadRequest(c *gin.Context, message string) {
	c.JSON(http.StatusBadRequest, Response{
		Code:    CodeBadRequest,
		Message: message,
	})
}

// Unauthorized 401错误
func Unauthorized(c *gin.Context, message string) {
	c.JSON(http.StatusUnauthorized, Response{
		Code:    CodeUnauthorized,
		Message: message,
	})
}

// Forbidden 403错误
func Forbidden(c *gin.Context, message string) {
	c.JSON(http.StatusForbidden, Response{
		Code:    CodeForbidden,
		Message: message,
	})
}

func ForbiddenWithCode(c *gin.Context, code int, message string) {
	c.JSON(http.StatusForbidden, Response{
		Code:    code,
		Message: message,
	})
}

// NotFound 404错误
func NotFound(c *gin.Context, message string) {
	c.JSON(http.StatusNotFound, Response{
		Code:    CodeNotFound,
		Message: message,
	})
}

// TooManyRequests 429错误
func TooManyRequests(c *gin.Context, message string) {
	c.JSON(http.StatusTooManyRequests, Response{
		Code:    CodeTooMany,
		Message: message,
	})
}

// ServerError 500错误
func ServerError(c *gin.Context, message string) {
	c.JSON(http.StatusInternalServerError, Response{
		Code:    CodeServerError,
		Message: message,
	})
}

// PageData 分页数据
type PageData struct {
	List     interface{} `json:"list"`
	Total    int64       `json:"total"`
	Page     int         `json:"page"`
	PageSize int         `json:"page_size"`
	HasMore  bool        `json:"has_more"`
}

// SuccessWithPage 分页响应
func SuccessWithPage(c *gin.Context, list interface{}, total int64, page, pageSize int) {
	hasMore := int64(page*pageSize) < total
	Success(c, PageData{
		List:     list,
		Total:    total,
		Page:     page,
		PageSize: pageSize,
		HasMore:  hasMore,
	})
}
