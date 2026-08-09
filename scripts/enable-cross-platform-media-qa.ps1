#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$MySqlContainer = "genericim-mysql",
    [string]$Database = "genericim",
    [string]$DatabaseUser = "genericim",
    [string]$DatabasePassword = "genericim"
)

$ErrorActionPreference = "Stop"

$sql = @'
UPDATE system_settings
SET value='["android","ios","windows","web"]', updated_at=NOW()
WHERE id=140 AND `key`='chat_image_direct_upload_platforms';

UPDATE system_settings
SET value='true', updated_at=NOW()
WHERE id=141 AND `key`='chat_image_direct_upload_enabled';

UPDATE system_settings
SET value='100', updated_at=NOW()
WHERE id=142 AND `key`='chat_image_direct_upload_rollout_percent';

SELECT id, `key`, value
FROM system_settings
WHERE id BETWEEN 140 AND 143
ORDER BY id;
'@

$dockerArgs = @(
    "exec",
    "-i",
    "-e",
    "MYSQL_PWD=$DatabasePassword",
    $MySqlContainer,
    "mysql",
    "-u$DatabaseUser",
    $Database
)

$sql | & docker @dockerArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to enable cross-platform media QA settings."
}
