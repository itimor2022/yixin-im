// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"genericim/internal/models"
)

const jpushPushEndpoint = "https://api.jpush.cn/v3/push"

func (s *PushService) sendJPush(device models.UserDevice, title, body string, data map[string]interface{}) error {
	s.configMu.RLock()
	cfg := s.androidConfig
	s.configMu.RUnlock()
	appKey := strings.TrimSpace(cfg.JPushAppKey)
	masterSecret := strings.TrimSpace(cfg.JPushMasterSecret)
	if !cfg.JPushEnabled {
		return fmt.Errorf("极光推送未启用")
	}
	if appKey == "" || masterSecret == "" {
		return fmt.Errorf("极光推送配置不完整")
	}
	dataMap := stringifyPushData(data)
	if dataMap == nil {
		dataMap = map[string]string{}
	}
	if strings.TrimSpace(title) != "" {
		dataMap["title"] = title
	}
	if strings.TrimSpace(body) != "" {
		dataMap["body"] = body
	}
	pushCategory := strings.TrimSpace(dataMap["push_category"])
	classification := 1
	if pushCategory == "marketing" || pushCategory == "marketing_notice" {
		classification = 0
	}
	alert := strings.TrimSpace(body)
	if alert == "" {
		alert = strings.TrimSpace(title)
	}
	payload := map[string]interface{}{
		"platform": "all",
		"audience": map[string]interface{}{
			"registration_id": []string{strings.TrimSpace(device.PushToken)},
		},
		"notification": map[string]interface{}{
			"alert": alert,
			"android": map[string]interface{}{
				"alert":  alert,
				"title":  title,
				"extras": dataMap,
			},
			"ios": map[string]interface{}{
				"alert": map[string]string{
					"title": title,
					"body":  body,
				},
				"sound":  "default",
				"extras": dataMap,
			},
		},
		"message": map[string]interface{}{
			"title":       title,
			"msg_content": body,
			"extras":      dataMap,
		},
		"options": map[string]interface{}{
			"apns_production": true,
			"classification":  classification,
		},
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal jpush body failed: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, jpushPushEndpoint, bytes.NewReader(bodyBytes))
	if err != nil {
		return fmt.Errorf("create jpush request failed: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Basic "+base64.StdEncoding.EncodeToString([]byte(appKey+":"+masterSecret)))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send jpush request failed: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("jpush send failed: status=%d body=%s", resp.StatusCode, sanitizePushErrorBody(respBody))
	}
	log.Printf("[Push][JPush] Sent push to device=%s", device.DeviceID)
	return nil
}
