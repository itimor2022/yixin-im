# 通用 IM 客户完整源码交付说明

本包是当前已审核工作区的源码快照，包含：

- Android、iOS、Web、Windows、macOS 的 Flutter 客户端源码。
- Go 后端源码、数据库迁移和配置模板。
- 运营管理后台源码（admin）。
- 客服管理后台源码（admin-kf）。
- H5、Docker、宝塔部署和构建脚本。
- 产品图片、字体和表情资源。

源码基线提交：b1650e4e87f2cbc3002ad05f435fe1f468a7bb76

本包不包含生产环境凭据、私钥、云服务私密配置或项目方线上域名。源码及部署示例仅使用保留的示例域名，正式部署前必须替换为客户自有域名。

安全边界：已排除 Git 历史、node_modules、构建缓存、二进制文件、数据库备份、日志、用户上传、Android 签名文件、SSL 证书、私钥和本地环境配置。

开始使用前请依次阅读 README.md、SOURCE_DELIVERY.md、NOTICE.md、docs/CONFIGURATION.md 和 docs/OPERATIONS.md。
