# Amazon S3 P1 直传上线说明

## 1. 本次上线能力

- 视频、普通文件优先使用 S3 预签名直传；
- 小于 100 MB 使用单次 PUT；
- 大于等于 100 MB 使用 16 MB multipart；
- 每个分片失败最多重试 3 次；
- App 重试时从 S3 查询已上传分片，只上传缺失部分；
- 完成时由后端校验分片连续性、对象大小、MIME 和可用的 SHA-256；
- 主动取消调用 S3 AbortMultipartUpload；
- 超时任务由后端清理，S3 再用 7 天生命周期兜底；
- 聊天成员可凭 `media_id` 获取 10 分钟 S3 签名访问 URL；
- 原 `/upload/*` P0 接口保留，未启用 S3 时自动回退。

## 2. 新增接口

```text
POST /api/v1/media/uploads/init
GET  /api/v1/media/uploads/{media_id}
POST /api/v1/media/uploads/{media_id}/parts/presign
POST /api/v1/media/uploads/{media_id}/complete
POST /api/v1/media/uploads/{media_id}/abort
GET  /api/v1/media/{media_id}/access-url
```

客户端不能保存 AWS Access Key 或 Secret。所有 S3 URL 都由已登录的后端临时签发。

## 3. S3 CORS

将 `https://app.example.com` 替换为真实 H5 域名；原生 App 不依赖浏览器 CORS，但 H5 必须配置。

```json
[
  {
    "AllowedOrigins": [
      "https://app.example.com"
    ],
    "AllowedMethods": [
      "GET",
      "HEAD",
      "PUT"
    ],
    "AllowedHeaders": [
      "content-type",
      "cache-control",
      "x-amz-*"
    ],
    "ExposeHeaders": [
      "ETag",
      "x-amz-checksum-sha256"
    ],
    "MaxAgeSeconds": 3600
  }
]
```

不要在生产环境长期使用 `AllowedOrigins: ["*"]`。

## 4. 未完成分片生命周期

```json
{
  "Rules": [
    {
      "ID": "abort-incomplete-chat-media",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "uploads/"
      },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }
  ]
}
```

后端会先清理 1 小时未继续的上传；7 天规则用于进程停机、数据库故障等情况下的最终兜底。

## 5. 后端 IAM 最小权限

将资源 ARN 替换为真实 Bucket：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GenericIMMediaObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::YOUR_BUCKET/uploads/*"
    }
  ]
}
```

生产环境建议开启 S3 Block Public Access。若聊天媒体必须私密，客户端展示或下载前使用 `access-url`，不要长期缓存签名 URL。

## 6. 上线顺序

1. 先部署后端，让数据库自动增加 P1 字段；
2. 配置 IAM、Bucket CORS、7 天 multipart 生命周期；
3. 用测试账号验证 10 MB 单 PUT、120 MB multipart、取消和续传；
4. 再发布 Flutter 客户端；
5. 观察 `media_objects` 中 `uploading/uploaded/bound/deleting/deleted` 数量；
6. 稳定后再对 VIP/SVIP 正式开放 300 MB～2 GB 权益。

## 7. 必测场景

- 同一个 `client_request_id` 重复 init 不生成第二个对象；
- 120 MB 文件上传到一半断网，恢复后不重传已完成分片；
- complete 请求重复调用返回同一个 `media_id`；
- 文件扩展名和 MIME 不匹配时 init 被拒绝；
- 普通成员不能访问未加入会话的媒体；
- 上传取消后 S3 不残留 multipart 计费分片；
- H5 的 OPTIONS/PUT 不被 CORS 拦截；
- Android、iOS、H5 分别完成至少一次真实 S3 上传和播放/下载。

## 8. 当前上线边界

- 本代码已完成直传、续传、重试、完成校验、取消、回收和短期访问 URL；
- 视频封面继续使用现有客户端抽帧上传流程；
- HEIC 转换、服务端视频转码、病毒扫描属于媒体处理基础设施，未在本地代码中假装完成；
- 没有真实 AWS 凭证时，只能完成编译、单元测试和兼容 S3 接口测试，生产上线前仍需真实 Bucket 与真机验收。
