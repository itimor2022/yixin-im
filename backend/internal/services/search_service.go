package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/elastic/go-elasticsearch/v8"
	"github.com/elastic/go-elasticsearch/v8/esapi"
)

// ESMessageDoc ES中存储的消息文档
type ESMessageDoc struct {
	MsgID      string `json:"msg_id"`
	ChatID     string `json:"chat_id"`
	SenderID   string `json:"sender_id"`
	SenderName string `json:"sender_name"`
	Type       int    `json:"type"`
	Content    string `json:"content"`
	Seq        uint64 `json:"seq"`
	CreatedAt  int64  `json:"created_at"`
	IsRevoked  bool   `json:"is_revoked"`
}

// SearchResult 搜索结果
type SearchResult struct {
	MsgID      string `json:"msg_id"`
	ChatID     string `json:"chat_id"`
	SenderID   string `json:"sender_id"`
	SenderName string `json:"sender_name"`
	Content    string `json:"content"`
	Highlight  string `json:"highlight"`
	Seq        uint64 `json:"seq"`
	CreatedAt  int64  `json:"created_at"`
}

// SearchService 搜索服务，ES未配置时自动降级
type SearchService struct {
	es      *elasticsearch.Client
	index   string
	enabled bool
}

// NewSearchService 初始化搜索服务，addresses为空时返回disabled实例
func NewSearchService(addresses []string, username, password, index string) *SearchService {
	if len(addresses) == 0 {
		log.Println("[Search] ES未配置，搜索功能降级为MongoDB正则搜索")
		return &SearchService{enabled: false}
	}
	if index == "" {
		index = "yixin_messages"
	}
	cfg := elasticsearch.Config{
		Addresses: addresses,
		Username:  username,
		Password:  password,
	}
	client, err := elasticsearch.NewClient(cfg)
	if err != nil {
		log.Printf("[Search] ES客户端初始化失败: %v，降级为MongoDB搜索", err)
		return &SearchService{enabled: false}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	res, err := client.API.Ping(client.Ping.WithContext(ctx))
	if err != nil || res.IsError() {
		log.Printf("[Search] ES连接失败，降级为MongoDB搜索")
		return &SearchService{enabled: false}
	}
	svc := &SearchService{es: client, index: index, enabled: true}
	if err := svc.ensureIndex(context.Background()); err != nil {
		log.Printf("[Search] ES索引初始化失败: %v", err)
	}
	log.Printf("[Search] ES连接成功，index=%s", index)
	return svc
}

// IsEnabled ES是否可用
func (s *SearchService) IsEnabled() bool {
	return s.enabled
}

// ensureIndex 创建索引和IK分词mapping（幂等）
func (s *SearchService) ensureIndex(ctx context.Context) error {
	res, err := s.es.Indices.Exists([]string{s.index}, s.es.Indices.Exists.WithContext(ctx))
	if err != nil {
		return err
	}
	if res.StatusCode == 200 {
		return nil
	}
	mapping := `{
		"settings": {
			"number_of_shards": 1,
			"number_of_replicas": 0,
			"analysis": {
				"analyzer": {
					"ik_smart_analyzer": {"type": "custom", "tokenizer": "ik_smart"}
				}
			}
		},
		"mappings": {
			"properties": {
				"msg_id":      {"type": "keyword"},
				"chat_id":     {"type": "keyword"},
				"sender_id":   {"type": "keyword"},
				"sender_name": {"type": "keyword"},
				"content":     {"type": "text", "analyzer": "ik_smart",
					"fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
				"sent_at":     {"type": "date"}
			}
		}
	}`
	req := esapi.IndicesCreateRequest{Index: s.index, Body: strings.NewReader(mapping)}
	res, err = req.Do(ctx, s.es)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.IsError() {
		return fmt.Errorf("创建ES索引失败: %s", res.String())
	}
	log.Printf("[Search] ES索引创建成功: %s", s.index)
	return nil
}

// IndexMessage 异步写入消息到ES（仅type=1文字消息）
func (s *SearchService) IndexMessage(doc ESMessageDoc) {
	if !s.enabled {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		data, err := json.Marshal(doc)
		if err != nil {
			log.Printf("[Search] ES序列化失败 msg_id=%s err=%v", doc.MsgID, err)
			return
		}
		res, err := s.es.Index(
			s.index,
			bytes.NewReader(data),
			s.es.Index.WithDocumentID(doc.MsgID),
			s.es.Index.WithContext(ctx),
		)
		if err != nil {
			log.Printf("[Search] ES写入失败 msg_id=%s err=%v", doc.MsgID, err)
			return
		}
		defer res.Body.Close()
		if res.IsError() {
			log.Printf("[Search] ES写入错误 msg_id=%s resp=%s", doc.MsgID, res.String())
		}
	}()
}

// Search 全局搜索文字消息，支持分页和关键词高亮
func (s *SearchService) Search(ctx context.Context, keyword, chatID string, page, size int) ([]*SearchResult, int64, error) {
	if !s.enabled {
		return nil, 0, nil
	}
	if page <= 0 {
		page = 1
	}
	if size <= 0 || size > 50 {
		size = 20
	}
	from := (page - 1) * size

	// 构建查询：按 chat_id 过滤 + 全文搜索
	var queryClause interface{}
	if chatID != "" {
		queryClause = map[string]interface{}{
			"bool": map[string]interface{}{
				"must": []interface{}{
					map[string]interface{}{
						"bool": map[string]interface{}{
							"should": []interface{}{
								map[string]interface{}{
									"match": map[string]interface{}{
										"content": map[string]interface{}{
											"query":    keyword,
											"operator": "or",
										},
									},
								},
								map[string]interface{}{
									"wildcard": map[string]interface{}{
										"content.keyword": map[string]interface{}{
											"value": "*" + keyword + "*",
										},
									},
								},
							},
							"minimum_should_match": 1,
						},
					},
				},
				"filter": []interface{}{
					map[string]interface{}{
						"term": map[string]interface{}{
							"chat_id.keyword": chatID,
						},
					},
				},
			},
		}
	} else {
		queryClause = map[string]interface{}{
			"bool": map[string]interface{}{
				"should": []interface{}{
					map[string]interface{}{
						"match": map[string]interface{}{
							"content": map[string]interface{}{
								"query":    keyword,
								"operator": "or",
							},
						},
					},
					map[string]interface{}{
						"wildcard": map[string]interface{}{
							"content.keyword": map[string]interface{}{
								"value": "*" + keyword + "*",
							},
						},
					},
				},
				"minimum_should_match": 1,
			},
		}
	}
	query := map[string]interface{}{
		"from":  from,
		"size":  size,
		"query": queryClause,
		"highlight": map[string]interface{}{
			"fields": map[string]interface{}{
				"content": map[string]interface{}{
					"pre_tags":            []string{"<em>"},
					"post_tags":           []string{"</em>"},
					"fragment_size":       100,
					"number_of_fragments": 1,
				},
			},
		},
		"sort": []interface{}{
			map[string]interface{}{"created_at": map[string]interface{}{"order": "desc"}},
		},
	}

	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(query); err != nil {
		return nil, 0, err
	}
	res, err := s.es.Search(
		s.es.Search.WithContext(ctx),
		s.es.Search.WithIndex(s.index),
		s.es.Search.WithBody(&buf),
	)
	if err != nil {
		return nil, 0, err
	}
	defer res.Body.Close()
	if res.IsError() {
		return nil, 0, fmt.Errorf("ES搜索失败: %s", res.String())
	}

	var esResp struct {
		Hits struct {
			Total struct {
				Value int64 `json:"value"`
			} `json:"total"`
			Hits []struct {
				Source    ESMessageDoc        `json:"_source"`
				Highlight map[string][]string `json:"highlight"`
			} `json:"hits"`
		} `json:"hits"`
	}
	if err := json.NewDecoder(res.Body).Decode(&esResp); err != nil {
		return nil, 0, err
	}

	results := make([]*SearchResult, 0, len(esResp.Hits.Hits))
	for _, hit := range esResp.Hits.Hits {
		r := &SearchResult{
			MsgID:      hit.Source.MsgID,
			ChatID:     hit.Source.ChatID,
			SenderID:   hit.Source.SenderID,
			SenderName: hit.Source.SenderName,
			Content:    hit.Source.Content,
				Seq:        hit.Source.Seq,
				CreatedAt:  hit.Source.CreatedAt,
			Highlight:  hit.Source.Content,
		}
		if hl, ok := hit.Highlight["content"]; ok && len(hl) > 0 {
			r.Highlight = hl[0]
		}
		results = append(results, r)
	}
	return results, esResp.Hits.Total.Value, nil
}

// DeleteMessage 从ES删除消息（消息撤回时调用）
func (s *SearchService) DeleteMessage(msgID string) {
	if !s.enabled {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		res, err := s.es.Delete(s.index, msgID, s.es.Delete.WithContext(ctx))
		if err != nil {
			log.Printf("[Search] ES删除失败 msg_id=%s err=%v", msgID, err)
			return
		}
		defer res.Body.Close()
	}()
}
