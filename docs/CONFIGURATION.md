# GenericIM Configuration

## Required Production Values

Set these values through environment variables or a protected runtime
configuration file:

- `GENERIC_IM_SERVER_MODE=release`
- `GENERIC_IM_SERVER_BASE_URL`
- `GENERIC_IM_ALLOWED_ORIGINS`
- `GENERIC_IM_WS_ALLOWED_ORIGINS`
- `GENERIC_IM_JWT_SECRET`
- `GENERIC_IM_SETTINGS_ENCRYPTION_KEY`
- `GENERIC_IM_MYSQL_*`
- `GENERIC_IM_MONGODB_*`
- `GENERIC_IM_REDIS_*`

Use strong, unique secrets. Never reuse the development values from
`compose.yaml`.

## Storage

The storage provider can be `local`, `aliyun`, `qiniu` or `s3`. Production
multi-node deployments should use S3-compatible object storage:

- `GENERIC_IM_STORAGE_PROVIDER=s3`
- `GENERIC_IM_STORAGE_S3_REGION`
- `GENERIC_IM_STORAGE_S3_BUCKET`
- `GENERIC_IM_STORAGE_S3_PUBLIC_BASE_URL`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

The access key must have only the required bucket permissions.

## Third-Party Services

Agora, LiveKit, Firebase, SMS and payment providers are optional integrations.
Keep their credentials in the deployment secret store. Example configuration
files may document variable names but must not contain real values.

## Configuration Precedence

Runtime database settings are authoritative for settings managed by the admin
panel. Environment variables and YAML provide defaults and fill missing
values. Confirm the final effective configuration from the service diagnostics
endpoint instead of assuming a local file was loaded.
