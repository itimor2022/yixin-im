# Amazon S3 P0 部署配置

> P0 已支持服务端代理上传。超过 100 MB 的视频和文件需等待 P1 直传/分片上传。

## 1. AWS 资源

1. 创建独立生产 Bucket，并开启全部 Block Public Access。
2. Object Ownership 选择 `Bucket owner enforced`。
3. 创建 CloudFront Distribution，S3 Origin 使用 OAC。
4. 将媒体域名指向 CloudFront，例如 `media.example.com`。
5. 创建仅用于媒体 Bucket 的 IAM 用户/访问密钥，并绑定下面的最小权限。

后端所需最小权限示例：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::YOUR_BUCKET/uploads/*"
    }
  ]
}
```

CloudFront OAC 的 Bucket Policy 按 AWS 控制台生成的 Distribution ARN 配置，不开放匿名 S3 访问。

## 2. 后台数据库配置

管理后台进入“系统配置 → 存储配置”，选择 Amazon S3，填写：

- Access Key ID
- Secret Access Key
- Region
- Bucket
- CloudFront/媒体访问域名
- 自定义 Endpoint（Amazon S3 留空）

保存后，AWS 两个密钥使用 AES-GCM 加密写入 MySQL
`system_settings.cloud_storage`，管理接口只返回 `******`，App/H5
永远不会收到 AWS 密钥。生产环境应配置独立的
`GENERIC_IM_SETTINGS_ENCRYPTION_KEY`；未配置时后端暂以 JWT Secret
派生加密密钥。

Amazon S3 原生服务必须保持 Endpoint 为空。只有 MinIO 等 S3
兼容服务才填写完整 Endpoint，并按需要开启 Path Style。

## 3. 上线检查

1. 更新后端，启动时自动迁移 `media_objects` 表。
2. 管理后台进入“系统设置 → 云存储”，选择 Amazon S3 并保存。
3. 点击“测试上传”，确认写入、CloudFront 访问和删除全部成功。
4. 检查数据库中 AWS 密钥字段以 `enc:v1:` 开头且不存在明文密钥。
5. 分别上传图片、MP4、语音、PDF、DOCX、XLSX、PPTX、TXT、CSV、ZIP。
6. 使用两台真机完成发送、接收、图片查看、视频拖动播放、文件下载。
7. 后台接口 `/api/v1/admin/upload/media-objects` 检查状态由 `uploaded` 变为 `bound`。
8. 验证伪造 MIME、危险双后缀、脚本和可执行文件均被拒绝。
9. 观察上传失败率和删除重试日志至少 24 小时。

## 4. 回滚

将后台 provider 切回 `local` 即可恢复新文件本地落盘。不要删除 S3、CloudFront、`media_objects` 表或原 `uploads` 目录；已经发送的 S3 媒体仍依赖原 CloudFront 域名访问。
