package config

import (
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server       ServerConfig       `yaml:"server"`
	MySQL        MySQLConfig        `yaml:"mysql"`
	MongoDB      MongoDBConfig      `yaml:"mongodb"`
	Redis        RedisConfig        `yaml:"redis"`
	JWT          JWTConfig          `yaml:"jwt"`
	WebSocket    WebSocketConfig    `yaml:"websocket"`
	MessageQueue MessageQueueConfig `yaml:"message_queue"`
	Shard        ShardConfig        `yaml:"shard"`
	Agora        AgoraConfig        `yaml:"agora"`
	Payment      PaymentConfig      `yaml:"payment"`
	SMS          SMSConfig          `yaml:"sms"`
}

type ServerConfig struct {
	Port                        int           `yaml:"port"`
	Mode                        string        `yaml:"mode"`
	ReadTimeout                 time.Duration `yaml:"read_timeout"`
	WriteTimeout                time.Duration `yaml:"write_timeout"`
	BaseURL                     string        `yaml:"base_url"`                       // 服务器外部访问地址
	RegisterBaseURL             string        `yaml:"register_base_url"`              // 注册页外部访问地址，留空则回退到 BaseURL
	UploadDir                   string        `yaml:"upload_dir"`                     // 上传文件存储目录，默认 ./uploads
	ExternalCleanupHTTPDelete   bool          `yaml:"external_cleanup_http_delete"`   // 是否允许服务端对外链执行 HTTP DELETE（默认 false）
	ExternalCleanupAllowedHosts []string      `yaml:"external_cleanup_allowed_hosts"` // 允许执行外部清理的主机白名单
}

type MySQLConfig struct {
	Host            string        `yaml:"host"`
	Port            int           `yaml:"port"`
	User            string        `yaml:"user"`
	Password        string        `yaml:"password"`
	Database        string        `yaml:"database"`
	MaxIdleConns    int           `yaml:"max_idle_conns"`
	MaxOpenConns    int           `yaml:"max_open_conns"`
	ConnMaxLifetime time.Duration `yaml:"conn_max_lifetime"`
}

type MongoDBConfig struct {
	URI         string `yaml:"uri"`
	Database    string `yaml:"database"`
	MaxPoolSize uint64 `yaml:"max_pool_size"`
	MinPoolSize uint64 `yaml:"min_pool_size"`
}

type RedisConfig struct {
	Addr         string `yaml:"addr"`
	Password     string `yaml:"password"`
	DB           int    `yaml:"db"`
	PoolSize     int    `yaml:"pool_size"`
	MinIdleConns int    `yaml:"min_idle_conns"`
}

type JWTConfig struct {
	Secret        string        `yaml:"secret"`
	Expire        time.Duration `yaml:"expire"`
	RefreshExpire time.Duration `yaml:"refresh_expire"`
}

type WebSocketConfig struct {
	ReadBufferSize  int           `yaml:"read_buffer_size"`
	WriteBufferSize int           `yaml:"write_buffer_size"`
	MaxMessageSize  int64         `yaml:"max_message_size"`
	PongWait        time.Duration `yaml:"pong_wait"`
	PingPeriod      time.Duration `yaml:"ping_period"`
	WriteWait       time.Duration `yaml:"write_wait"`
}

type MessageQueueConfig struct {
	ChannelBuffer int           `yaml:"channel_buffer"`
	Workers       int           `yaml:"workers"`
	BatchSize     int           `yaml:"batch_size"`
	FlushInterval time.Duration `yaml:"flush_interval"`
}

type ShardConfig struct {
	Count int `yaml:"count"`
}

type AgoraConfig struct {
	Enabled        bool   `yaml:"enabled"`
	AppID          string `yaml:"app_id"`
	AppCertificate string `yaml:"app_certificate"`
	TokenExpire    int    `yaml:"token_expire"`
}

// PaymentConfig 微信/支付宝在线充值（notify_base_url 为公网可访问的根，如 https://api.example.com）
// 管理后台可将密钥以 PEM 文本写入 private_key_pem / app_private_key_pem 等字段；与 yaml 文件配置二选一或互补。
type PaymentConfig struct {
	Enabled       bool    `json:"enabled" yaml:"enabled"`
	NotifyBaseURL string  `json:"notify_base_url" yaml:"notify_base_url"`
	MinAmount     float64 `json:"min_amount" yaml:"min_amount"`
	MaxAmount     float64 `json:"max_amount" yaml:"max_amount"`
	Wechat        struct {
		Enabled              bool   `json:"enabled" yaml:"enabled"`
		MchID                string `json:"mch_id" yaml:"mch_id"`
		MchAPIv3Key          string `json:"mch_api_v3_key" yaml:"mch_api_v3_key"`
		MchCertificateSerial string `json:"mch_certificate_serial" yaml:"mch_certificate_serial"`
		AppID                string `json:"app_id" yaml:"app_id"`
		PrivateKeyPath       string `json:"private_key_path,omitempty" yaml:"private_key_path"`
		PrivateKeyPEM        string `json:"private_key_pem,omitempty" yaml:"private_key_pem,omitempty"`
		H5AppName            string `json:"h5_app_name" yaml:"h5_app_name"`
		H5AppURL             string `json:"h5_app_url" yaml:"h5_app_url"`
		H5BundleID           string `json:"h5_bundle_id,omitempty" yaml:"h5_bundle_id"`
		H5PackageName        string `json:"h5_package_name,omitempty" yaml:"h5_package_name"`
	} `json:"wechat" yaml:"wechat"`
	Alipay struct {
		Enabled             bool   `json:"enabled" yaml:"enabled"`
		AppID               string `json:"app_id" yaml:"app_id"`
		PrivateKeyPath      string `json:"private_key_path,omitempty" yaml:"private_key_path"`
		AppPrivateKeyPEM    string `json:"app_private_key_pem,omitempty" yaml:"app_private_key_pem,omitempty"`
		AlipayPublicKeyPath string `json:"alipay_public_key_path,omitempty" yaml:"alipay_public_key_path"`
		AlipayPublicKeyPEM  string `json:"alipay_public_key_pem,omitempty" yaml:"alipay_public_key_pem,omitempty"`
		IsProduction        bool   `json:"is_production" yaml:"is_production"`
		ReturnURL           string `json:"return_url,omitempty" yaml:"return_url"`
	} `json:"alipay" yaml:"alipay"`
}

// SMSConfig 短信发送（绑定手机号验证码）；provider: smsbao | aliyun | tencent
type SMSConfig struct {
	Enabled         bool   `json:"enabled" yaml:"enabled"`
	Provider        string `json:"provider" yaml:"provider"`                 // smsbao | aliyun | tencent
	MessageTemplate string `json:"message_template" yaml:"message_template"` // 仅短信宝：正文，需含占位符 {code}
	SMSBao          struct {
		User     string `json:"user" yaml:"user"`
		Password string `json:"password" yaml:"password"` // 登录密码，传输 MD5
	} `json:"smsbao" yaml:"smsbao"`
	Aliyun struct {
		AccessKeyID     string `json:"access_key_id" yaml:"access_key_id"`
		AccessKeySecret string `json:"access_key_secret" yaml:"access_key_secret"`
		Region          string `json:"region" yaml:"region"`
		SignName        string `json:"sign_name" yaml:"sign_name"`
		TemplateCode    string `json:"template_code" yaml:"template_code"`
	} `json:"aliyun" yaml:"aliyun"`
	Tencent struct {
		SecretID   string `json:"secret_id" yaml:"secret_id"`
		SecretKey  string `json:"secret_key" yaml:"secret_key"`
		Region     string `json:"region" yaml:"region"`
		SdkAppID   string `json:"sdk_app_id" yaml:"sdk_app_id"`
		SignName   string `json:"sign_name" yaml:"sign_name"`
		TemplateID string `json:"template_id" yaml:"template_id"`
	} `json:"tencent" yaml:"tencent"`
}

var GlobalConfig *Config

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	if cfg.JWT.RefreshExpire <= 0 {
		cfg.JWT.RefreshExpire = 90 * 24 * time.Hour
	}

	GlobalConfig = &cfg
	return &cfg, nil
}
