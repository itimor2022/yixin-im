// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"errors"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"time"
	"genericim/internal/config"
	"genericim/internal/middleware"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
)

// SmsSettingsHandler 管理后台短信网关配置
type SmsSettingsHandler struct {
	db     *gorm.DB
	cfg    *config.Config
	smsSvc *services.SMSService
}

func NewSmsSettingsHandler(db *gorm.DB, cfg *config.Config, smsSvc *services.SMSService) *SmsSettingsHandler {
	return &SmsSettingsHandler{db: db, cfg: cfg, smsSvc: smsSvc}
}

func maskSMSConfigForDemo(c config.SMSConfig) config.SMSConfig {
	out := c
	out.SMSBao.Password = maskSecret(out.SMSBao.Password)
	out.Aliyun.AccessKeySecret = maskSecret(out.Aliyun.AccessKeySecret)
	out.Tencent.SecretKey = maskSecret(out.Tencent.SecretKey)
	return out
}

func maskSecret(s string) string {
	if s == "" {
		return ""
	}
	return "******"
}

// GetSmsGatewayConfig GET /admin/settings/sms-gateway-config
func (h *SmsSettingsHandler) GetSmsGatewayConfig(c *gin.Context) {
	if h.cfg == nil {
		response.Error(c, http.StatusInternalServerError, "服务未配置")
		return
	}
	cfg := services.LoadSMSForRuntime(h.db, h.cfg.SMS)
	if middleware.GetAdminRole(c) == "demo_admin" {
		cfg = maskSMSConfigForDemo(cfg)
	}
	response.Success(c, cfg)
}

// SaveSmsGatewayConfig PUT /admin/settings/sms-gateway-config
func (h *SmsSettingsHandler) SaveSmsGatewayConfig(c *gin.Context) {
	if h.cfg == nil || h.smsSvc == nil {
		response.Error(c, http.StatusInternalServerError, "服务未配置")
		return
	}
	var body config.SMSConfig
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	raw, err := json.Marshal(body)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "序列化失败")
		return
	}
	now := time.Now()
	var row models.SystemSetting
	err = h.db.Where("`key` = ?", models.SettingSmsGateway).First(&row).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			if err := h.db.Create(&models.SystemSetting{
				Key: models.SettingSmsGateway, Value: string(raw), Type: "json",
				CreatedAt: now, UpdatedAt: now,
			}).Error; err != nil {
				response.Error(c, http.StatusInternalServerError, "保存失败")
				return
			}
		} else {
			response.Error(c, http.StatusInternalServerError, "保存失败")
			return
		}
	} else {
		if err := h.db.Model(&row).Updates(map[string]interface{}{"value": string(raw), "updated_at": now}).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "保存失败")
			return
		}
	}
	h.smsSvc.InvalidateSMSCache()
	response.Success(c, gin.H{"message": "保存成功"})
}
