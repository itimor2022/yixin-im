param(
    [string]$Container = "genericim-mysql",
    [string]$Database = "genericim",
    [string]$User = "root",
    [string]$Password = "genericim_root"
)

$ErrorActionPreference = "Stop"

$packs = @(
    @{
        PackID = "cubigator"
        Name = "小恐龙"
        Description = "小恐龙动画贴纸"
        PreviewEmoji = "🦖"
        Dir = "cubigator"
        Prefix = "cubigator"
        Count = 30
        SortOrder = 20
    },
    @{
        PackID = "duck"
        Name = "小黄鸭"
        Description = "小黄鸭动画贴纸"
        PreviewEmoji = "🐤"
        Dir = "duck"
        Prefix = "duck"
        Count = 29
        SortOrder = 21
    },
    @{
        PackID = "premium_gifts"
        Name = "高级礼品"
        Description = "高级礼品动画贴纸"
        PreviewEmoji = "🎁"
        Dir = "premium_gifts"
        Prefix = "premium_gifts"
        Count = 30
        SortOrder = 22
    }
)

function SqlString([string]$Value) {
    return "'" + ($Value -replace "'", "''") + "'"
}

$statements = @("SET NAMES utf8mb4;")

foreach ($pack in $packs) {
    $files = for ($i = 1; $i -le [int]$pack.Count; $i++) {
        SqlString ("/uploads/stickers/$($pack.Dir)/$($pack.Prefix)_$($i.ToString("00")).gif")
    }
    $filesSql = "JSON_ARRAY(" + ($files -join ",") + ")"
    $previewFile = "/uploads/stickers/$($pack.Dir)/$($pack.Prefix)_01.gif"

    $statements += @"
INSERT INTO emoji_store_pack_catalogs
    (pack_id, name, description, preview_emoji, preview_file, sticker_files, sort_order, is_built_in, is_active, created_at, updated_at)
VALUES
    ($(SqlString $pack.PackID), $(SqlString $pack.Name), $(SqlString $pack.Description), $(SqlString $pack.PreviewEmoji), $(SqlString $previewFile), $filesSql, $($pack.SortOrder), 1, 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    description = VALUES(description),
    preview_emoji = VALUES(preview_emoji),
    preview_file = VALUES(preview_file),
    sticker_files = VALUES(sticker_files),
    sort_order = VALUES(sort_order),
    is_built_in = VALUES(is_built_in),
    is_active = VALUES(is_active),
    updated_at = NOW();
"@
}

$statements += "SELECT pack_id, name, preview_file, JSON_LENGTH(sticker_files) AS sticker_count, is_active, sort_order FROM emoji_store_pack_catalogs WHERE pack_id IN ('cubigator','duck','premium_gifts') ORDER BY sort_order;"
$sql = $statements -join "`n"

$mysqlArgs = @(
    "exec",
    "-i",
    $Container,
    "mysql",
    "--default-character-set=utf8mb4",
    "-u$User",
    "-p$Password",
    $Database
)

$sql | docker @mysqlArgs
